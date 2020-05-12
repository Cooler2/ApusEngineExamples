
// Author: Alexey Stankevich (Apus Software)
unit UOutput;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$R+}

interface
uses types,Cnsts,MyServis{$IFNDEF server},cards{$ENDIF};
const
 AnimationSpeed=600;
 titleNames:array[1..6] of string=('Novice mage','Mage','Advanced mage','Expert Mage','Magister','Archmage');

type

tmessageItem=record
 startpos,endpos:integer;
 s:string[80];
 cardnum:integer;  // 0 - just a word
end;

tmessage=record
 numItems:integer;
 mesItems:array[1..50] of tMessageItem;
 sender:string[32];
 msgtext:string;
 colorselect:boolean;
end;

tmessagesblock=record
 messages:array[0..31] of tMessage;
 nummes:integer; // количество видимых строк лога
 addy:integer;
 neednewcolorselect:boolean;
 totalLines:integer; // кол-во вообще всех строк, когда-либо добавленных в лог
end;

Tdeadcreature=record
 player, number, alpha:integer;
end;

tcastedcard=record
 startpos,startspeed,curpos,endpos:tpoint;
 card:integer;
 starttime:int64;
 needfast:boolean;
end;

tsign=object
 starttime:int64;
 startX,startY:integer;
 curX,curY:integer;
 font:integer;
 linkedpl,linkedcreature:integer;
 movesign:integer;   // -10..10
 signstr:string[7];
 signcolor:cardinal;
 UID:cardinal;
end;

tsigninfo=object
 signs:array[1..128] of tsign;
 numsigns:integer;
 lastdamagedplayer,lastdamagevalue:integer;
 lastdamagetime:int64;
 procedure processsign(num:integer;processnext:boolean=true);
 // num1 = player (1..2)
 // num2 =  1..6 - жизнь кричи в указанном слоте
 //        11..16 - атака кричи в указанном слоте
 //          0 - жизнь игрока,
 //         -1 - power игрока
 //         -2 - мана игрока
 // delayType = 1 (атака кричей)
 procedure AddSign(player,item,value:integer;delayType:integer=0); {$ifdef aitesting}inline;{$endif}
end;

// Эффект, связанный с панелью игрока
TPlayerEffect=(
  plrEffLosePower = 1, // потеря павера
  plrEffGainPower = 2, // получение дополнительного павера (не в начале хода)
  plrEffGainMana = 3,  // получение маны
  plrEffHeal = 4,      // лечение
  plrEffDamage = 5);   // получение урона (доп. параметр)

type

 TOptInfo=object
  SoundVolume,MusicVolume:integer; //1-9 (for audio 1-disabled)
  FullScreen,AutoEndTurn,IgnoreGuildInvites:boolean;
  language:byte;
  avoidBots:boolean;
  hideDescriptions:boolean;
  tempbytes:array[3..63] of byte;
 end;

var
 optInfo:TOptInfo;

const
 HandCardZ = 1; // дефолтное значение Z у карт в руке (у крич в бою - 0)
 ActingCreatureZ = 1.2; // значение Z у крич, действующих в бою
 FlyingCardZ = 3; // значение Z, достигаемое картами в обычном движении к слотам

var
   LockLogic:TMyCriticalSection; // используется для защиты всех глобальных данных, так или иначе касающихся отрисовки

//    curActivatedCard:smallint;                   // <0 - creature ability
//    CreaturesXY:array[1..2,1..6,1..3] of tPoint; //1 current, 2 start, 3 final
//    CreatureScale:array[1..2,1..6,1..3] of smallint; // persents
//    CardsXY:array[1..2,1..8,1..3] of tPoint; //1 current, 2 start, 3 final
    slots,saveslots:array[1..2,1..6] of shortint;          // 0 - usual, 1 - available for creature, 2- available as target
    DeadCreature:Tdeadcreature;
    CastedCard:tCastedCard;
    MesBlock:tMessagesBlock;
    MessageToAdd,CurSender:string;
    turnisfinished,attackphase:boolean;
    signinfo:tsigninfo;
    skipback:boolean;
//    ActingSpell:integer;
    showmovecard:boolean=true;
    lastcardcomment:integer;
    widescreen:boolean=true;
    bigWindow:boolean=false; // Развернуть окно побольше
    // Насколько реальная область отрисовки больше базового разрешения,
    // на которое ориентируются скрипты (1024x768, либо 1366x768)
    // Этот коэффициент применяется при отрисовке изображений, созданных для базовых разрешений
    ScreenScaleX,ScreenScaleY:single;
    // Степень сжатия/растяжения базы окна - sqrt(min(screenScaleX,screenScaleY)) - единый масштаб для окон
    windowScale:single;
    // Поправочный коэффициент к ScreenScale для изображений, созданных для HD-разрешений
    // 1920x1080 либо 2048x1536
    HDmagic:single = 1366/1920;
    // Используется ли HD-графика (для широкоэкранного режима - всегда (вроде бы) true)
    HDMode:boolean=true;

    glVersion:single; // Версия OpenGL

    instanceID:cardinal=0; // уникальный (более-менее) код экземпляра игры
    // различные флаги о том, что делает юзер в процессе сессии
    // 1 - открыл окно покупки премиума
    // 2 - открыл окно покупки голды
    // 4 - открыл окно маркета
    // 8 - открыл окно миссий
    // 16 - открыл меню "Еще"
    // 32 - посмотрел карту крупным планом
    usageFlags:cardinal=0;

    loadingTime:integer=0; // время (в 0.1c от старта игры до перехода в экран логина)

    fontScale:single=1.0; // коэффициент увеличения шрифтов относительно выбранных для базовых разрешений
    fontScale2:single=1.0; // то же самое, но для текста в пропорциональных элементах (таких, как кнопки) - изменяется ближе к линейному

    animationStartTime:int64=0;  // Время начала какой-то анимации (вызов ShowMes с firstlaunch=true) (по сути не нужно)
    animationEndTime:int64=0;  // Время завершения анимации (выставляется в коде эффектов)
    addCounter:integer; // Счетчик сообщений в логе/чате
    suspendedDelayTime:integer;

    logLineHeight:integer=21; // межстрочный интервал в combat log

    tutorialPause:boolean=false;
    needTutorials:integer=0;    // 1 about creature attack creature, 2 about creature attack player, 4 about card replacing, 8 about creature stats
    dragmode,dragforced:boolean;
    dragx,dragy,dragofsx,dragofsy,forcedX,forcedY,dragcard:integer;
    canendturn:boolean;
    ShowMestm:int64;
    cardZoomForbidden:boolean=false;

function ConstructMessage(var m:tMessage;s:string;maxwidth:integer=900;tag:integer=0;sender:string=''):string;
procedure ShowMes(mes:string;tag:integer=0;firstlaunch:boolean=true;sender:string='';instant:boolean=false); {$ifdef aitesting}inline;{$endif}
procedure ActivateCard(num:integer);
procedure ActivateAbility(num:integer);
procedure forcelogmessage(s:string);
procedure PrepareCombat;
procedure SignalOut(event:String;tag:integer=0);
//procedure DelayedSignalU(event:string;delay:integer;tag:integer=0); inline;
procedure CreatureAct(pl,num:integer;needeffect:boolean=true); {$ifdef aitesting}inline;{$endif}
procedure MarkCreature(pl,num:integer);
procedure HighlightCreature(pl,num:integer);

// На существо подействовала другая карта
procedure AutoSave;
// n>=1000 - абилка
procedure ShowCardInfo(n,comment,target:integer);
procedure MouseCheck;
procedure GameOver;

procedure LockDrawing;
procedure LeaveDrawing;

{$IFNDEF server}
function creaturepos(pl,num:integer):tpoint;
function cardpos(pl,num:integer;handmodifier:integer=0;handCardsCnt:integer=0):tpoint;
function pressedcardpos(pl,num:integer):tpoint;
function deckpos(pl:integer):tpoint;

function facepos(pl:integer):tpoint;
function namestringpos(pl:integer):tpoint;
function lifestringpos(pl:integer):tpoint;
function spellpowerstringpos(pl:integer):tpoint;
function manastringpos(pl:integer):tpoint;

procedure ClearCombatLog;
function TranslatedFile(fname:string):string;
{$ENDIF}

procedure EFF_ManaStorm;
procedure EFF_AbilityUsed(player,card,target:integer;afterMsg:boolean);

procedure EFF_AddManaStorm;
procedure EFF_RemoveManaStorm;
procedure waitAnimation;

// Добавляет новую карту в руку игрока (если надо - производит сдвиг колоды и/или потерю карты)
// cardGiver - крича, дающая новую карту (0 - нет, 11..16 - кричи 1-го игрока, 21..26 - второго)
procedure EFF_AddHandCard(player,card:integer;cardGiver:integer=0);

// Игрок player использует карту из руки под номером index: это заклинание, летящее в слот target
// (target=0 - заклинание без цели, 1..6 - свои слоты, -1..-6 - слоты противника)
// card - тип карты (от этого может зависеть эффект, связанный с полетом карты)
procedure EFF_CastSpell(player,index,target,card:integer);

// Игрок player призывает существо из руки с индексом index в слот target (1..6)
// если index=0 - то существо берется не из руки, а просто создается на поле (исходя из данных дуэли)
procedure EFF_PlaceCreature(player,index,target:integer);

// Уведомление о том, что крича заменена на другую
procedure EFF_CreatureReplaced(player,index:integer);

// Игрок производит замену карты в руке под номером index на карту newCard
//procedure EFF_ReplaceHandCard(player,index,newCard:integer);

// Возвращает существо с поля боя в руку (handPlayer - в руку которого игрока возаращается карта)
procedure EFF_ReturnCreatureToHand(player,index,handPlayer:integer);

// Игрок тупо теряет карту из руки под номером index
procedure EFF_LoseHandCard(player,index:integer);

// Игрок теряет ВСЕ карты в руке
procedure EFF_LoseAllCards(player:integer);

// Существо погибает или уничтожается
procedure EFF_DestroyCreature(player,index:integer);

// Существо идет в атаку на слот напротив
procedure EFF_CreatureAttack(player,index:integer);

// Переносит кричу в другой слот
// mode = 1: переносит в пустой слот, если там что-то было - оно уничтожается
// mode = 2: обмен позициями
// mode = 3: переносит в слот, а затем возвращает назад (абилка?)
procedure EFF_MoveCreatureToSlot(player,index,newPlayer,newIndex:integer;mode:integer);

// Визуальный эффект, связанный с изменением параметров игрока
procedure EFF_PlayerEffect(player:integer;effect:TPlayerEffect;value:integer=0);

// Вспомогательные ф-ции
// Переводит прямоугольник из координат в стандартном режиме в текущий
function ScaledRect(x1,y1,x2,y2:integer;HD:boolean=true):TRect;
 // Находимся ли сейчас в экране боя (т.е. виден ли он)
 // если notClosing=true, то возвращает true только если экран боя в рабочем режиме, а не в состоянии перехода
function CombatIsRunning(notClosing:boolean=false):boolean;

function OpponentType:integer; inline;

implementation
{$ifndef server}
uses
  sysutils,UDict,Geom2d,SyncObjs,
  enginetools,EngineCls,eventman,console,
  ULogicThread,UCombatResult,ULogic,UCombat,CombatEff,PartEff,UChatLogic;
{$endif}

var
 lastSignID:cardinal=0;

procedure DelayedSignal(event:String;delay:integer;tag:integer=0); inline;
begin
 {$ifndef server}
 eventman.delayedSignal(event,delay,tag);
 {$endif}
end;

procedure Signal(event:String;tag:integer=0); inline;
begin
 {$ifndef server}
 eventman.Signal(event,tag);
 {$endif}
end;

procedure SignalOut(event:String;tag:integer=0);
begin
 {$ifndef server}
 eventman.Signal(event,tag);
 {$endif}
end;


// Устанавливает время ожидания для ShowMes не менее чем animationSpeed*factor от текущего момента
procedure SetWaitFactor(factor:single=1.0);
 var
  t:int64;
 begin
  t:=MyTickCount+round(AnimationSpeed*factor);
  if t>animationEndTime then animationEndTime:=t;
 end;

function OpponentType:integer; inline;
 begin
  {$ifndef server}
  result:=gamelogic[0].playersinfo[2].control;
//  result:=-1;
 {$endif}
 end;

procedure LockDrawing;
begin
 {$ifndef server}
 asm
  mov edx,[esp]
  lea eax,lockLogic
  call EnterCriticalSection
 end;
 {$endif}
end;

function CombatIsRunning(notClosing:boolean=false):boolean;
begin
 {$ifdef SERVER}
  result:=true;
 {$else}
  result:=CombatMode.scene.status=ssActive;
  if result and notClosing then
   if CombatMode.scene.effect<>nil then result:=false;
 {$endif}
end;

procedure LeaveDrawing;
begin
 {$ifndef server}
 LockLogic.leave;
 {$endif}
end;

procedure MouseCheck;
begin
 {$ifndef server}
 {$ifndef aitesting}
 combatmode.mousemove(game.mouseX,game.mousey);
 {$endif}
 {$endif}
end;

procedure waitAnimation;
begin
 {$ifndef server}
 {$ifndef aitesting}
 animationStartTime:=MyTickCount;
 if mainDuel.Emulation=false then
 while MyTickCount<AnimationEndTime do sleep(5);
 {$endif}
 {$endif}
end;

procedure GameOver;
begin
 {$ifndef aitesting}
 {$ifndef server}
 Signal('SOUND\PLAYMUSIC\NONE');

 if mainDuel.winner=1 then
  Signal('SOUND\Play\WinDuel')
 else
 Signal('SOUND\Play\LoseDuel');
 ShowCombatResult;
 logicinfo.inAction:=false;
 attackphase:=false;
 {$endif}
 {$endif}
end;

{$IFNDEF server}
function facepos(pl:integer):tpoint;
begin
 if WideScreen then begin
  result.x:=round(173*ScreenScaleX);
  result.y:=round((126+(2-pl)*544-byte(widescreen)*35)*screenScaleY);
 end else begin
  result.x:=round(112*screenScaleX);
  result.y:=round((92+544*(2-pl))*screenScaleY);
 end;
end;

function namestringpos(pl:integer):tpoint;
begin
 if widescreen then
  result.X:=204
 else
  result.X:=132;
 result.Y:=12+(2-pl)*603;
end;

function lifestringpos(pl:integer):tpoint;
begin
 if pl=1 then begin
  result:=Point(plr1Life.x.IntValue,plr1Life.Y.IntValue);
 end else begin
  result:=Point(plr2Life.x.IntValue,plr2Life.Y.IntValue);
 end;
end;

function spellpowerstringpos(pl:integer):tpoint;
begin
 ASSERT(plr1Power.IsAlive AND plr2Power.IsAlive);
 if pl=1 then begin
  result:=Point(plr1Power.x.IntValue,plr1Power.Y.IntValue);
 end else begin
  result:=Point(plr2Power.x.IntValue,plr2Power.Y.IntValue);
 end;
end;

function manastringpos(pl:integer):tpoint;
begin
 ASSERT(plr1Mana.IsAlive AND plr2Mana.IsAlive);
 if pl=1 then begin
  result:=Point(plr1Mana.x.IntValue,plr1Mana.Y.IntValue);
 end else begin
  result:=Point(plr2Mana.x.IntValue,plr2Mana.Y.IntValue);
 end;
end;

function pressedcardpos(pl,num:integer):tpoint;
var q:integer;
begin
 result:=cardpos(pl,num);
end;

function cardpos(pl,num:integer;handmodifier:integer=0;handCardsCnt:integer=0):tpoint;
var q,n:integer;
begin
 if handCardsCnt=0 then begin
  for n:=1 to 8 do
   if handCards[pl,n]<>nil then inc(handCardsCnt);
 end;

 if not widescreen then
 begin
  result.X:=284+102*(num-1);
  inc(result.X,(8-handCardsCnt-handmodifier)*50-50);
  if handCardsCnt>=7 then dec(result.x,6);
 end
 else
 begin
  result.X:=429+116*(num-1);
  inc(result.X,(8-handCardsCnt-handmodifier)*58-58);
 end;
 result.x:=round(result.x*screenscalex);
 result.Y:=round(screenScaleY*(683+600*(1-pl)));

{ if widescreen=false then
  result.X:=(290+108*(num-1))
 else
  result.X:=round(ScreenScaleX*(418+112*(num-1)));
 result.Y:=round(screenScaleY*(684+600*(1-pl)));
 n:=mainDuel.players[pl].numhandcards;
 inc(result.X,(8-n-handmodifier)*54-70);
 if n>=7 then inc(result.x,10); }
end;

function creaturepos(pl,num:integer):tpoint;
begin
 if widescreen then begin
  result.X:=round((641+180*(num-1))*screenScaleX*HDMagic);
  result.Y:=round(screenScaleY*(641+207*(1-pl))*HDMagic);
 end else begin
  result.X:=round(screenScaleX*(330+103.4*(num-1)));
  result.Y:=round(screenScaleY*(456+150*(1-pl)));
 end;
end;

function deckpos(pl:integer):tpoint;
begin
 if widescreen=false then
  result.X:=1025
 else
  result.X:=1367;
 result.Y:=620+588*(1-pl);
end;

function outpos(pl,num:integer):tpoint;
begin
// result.X:=294+90*(num-1);
// result.Y:=-100000+134-400+(548-134+800)*(pl-1);
 result.X:=-90;
 result.Y:=maxint;
end;
{$ENDIF}

// n>=1000 - абилка
procedure ShowCardInfo(n,comment,target:integer);
var q,w,e,r,t:integer;
begin
 {$ifndef server}
 try
 if n<1000 then begin
  LockCards;
  handCards[2,comment].cardnum:=n;
  handCards[2,comment].cost:=mainDuel.getcost(2,n);
  handCards[2,comment].attack:=cardInfo[n].damage;
  handCards[2,comment].life:=cardInfo[n].life;
  handCards[2,comment].turn.Assign(Pi);
  handCards[2,comment].turn.Animate(0,300,spline0);
  UnlockCards;
  Signal('Sound\Play\CardRevealed');
 end else
  Signal('Sound\Play\AbilityDescription');

 if target<>0 then
 begin
  if target>0 then
   q:=mainDuel.curplayer
  else
   q:=mainDuel.enemy;
  w:=abs(target);
 end;

 if (optinfo.hideDescriptions) then
 begin
  if n>1000 then
  begin
   if target<>0 then
   begin
    creatures[2,comment].scale.Animate(1.06,250,spline0);
    slots[q,w]:=1;
    if (target=comment) then
     sleep(1250)
    else
     sleep(750);
    creatures[2,comment].scale.Animate(1,2000,spline0);
    fillchar(slots,sizeof(slots),0);
   end else
   begin
{    HighlightCreature(2,comment);
    Sleep(600);}
    creatures[2,comment].angle.Animate(-0.15,250,spline0);
    Sleep(300);
    creatures[2,comment].angle.Animate(0,250,spline0);
    Sleep(300);
{    creatures[2,comment].angle.Animate(-0.15,200,spline0);
    Sleep(200);
    creatures[2,comment].angle.Animate(0.15,300,spline0);
    Sleep(300);
    creatures[2,comment].angle.Animate(0,200,spline0);
    Sleep(200);}
   end;
  end else
  begin
   if cardinfo[n].life>0 then
    sleep(500)
   else
   if target<>0 then
   begin
    slots[q,w]:=1;
    sleep(1000);
    fillchar(slots,sizeof(slots),0);
   end else
    sleep(800)
  end;
 end
 else
  ShowCardDesc(n,comment,target);
 except on e:Exception do ForceLogMessage('Error in UO.SCI: '+ExceptionMsg(e)); end;
 {$endif}
end;

procedure MarkCreature(pl,num:integer);
var
{$ifndef server}
 card:TGameCard;
{$endif}
 t:integer;
begin
 {$ifndef server}
 {$ifndef aitesting}
 try
 if gamelogic[0].AIInfo.emulation then exit;
 SetWaitFactor(1);
 LockCards;
 try
 card:=creatures[pl,num];
 if (card<>nil) and (card.scale.FinalValue=1) then begin
  t:=animationSpeed div 2;
  card.scale.Animate(1.05,t,spline2);
  card.scale.Animate(1,t,spline2rev,t);
  card.z.Animate(ActingCreatureZ,t,spline2);
  card.z.Animate(0,t,spline2rev,t);
 end;
 finally
  UnlockCards;
 end;
 except on e:Exception do ForceLogMessage('Error in UO.MC: '+ExceptionMsg(e)); end;
 {$endif}
 {$endif}
end;

procedure HighlightCreature(pl,num:integer);
var
 t,cardtype:integer;
{$ifndef server}
 card:TGameCard;
 eff:string;
{$endif}
begin
 {$ifndef server}
 {$ifndef aitesting}
 try
// combateff.creatureact(pl,num,needeffect);
 if gamelogic[0].AIInfo.emulation then exit;
 SetWaitFactor(1.5);
 LockCards;
 try
 card:=creatures[pl,num];
 if (card<>nil) then begin
  TCreatureActEffect.Create(card);
  cardtype:=card.cardnum;

 end;
 finally
  UnlockCards;
 end;
 except on e:Exception do ForceLogMessage('Error in UO.HC: '+ExceptionMsg(e)); end;
 {$endif}
 {$endif}
end;

procedure CreatureAct(pl,num:integer;needeffect:boolean=true);
var
 t,cardtype:integer;
{$ifndef server}
 card:TGameCard;
 eff:string;
{$endif}
begin
 {$ifndef server}
 {$ifndef aitesting}
 try
// combateff.creatureact(pl,num,needeffect);
 if gamelogic[0].AIInfo.emulation then exit;
 SetWaitFactor(1.5);
 LockCards;
 try
 card:=creatures[pl,num];
 if (card<>nil) and (card.scale.finalValue=1) then begin
  t:=round(animationSpeed*0.6);
  card.scale.Animate(1.07,t,spline2);
  card.scale.Animate(1,t,spline2rev,t);
  card.z.Animate(ActingCreatureZ*2,t,spline2);
  card.z.Animate(0,t,spline2rev,t);
  TCreatureActEffect.Create(card);
  cardtype:=card.cardnum;

  // Damage: Priest of Fire (11), Siege Golem (142), Lich (53), Bargul (119), Banshee 79, Greater Demon (148)
  if cardtype in [11,142,53,79,119,148] then Signal('Sound\Play\TriggerDamage');
  // Attack Up: Battle Priest (8), Knight of Darkness (52), Vampire Lord (59), Elven Mystic (65),
  // Paladin (87), Holy Avenger (91), Lord of the Coast (93), Seeker for Knowledge (94), Devourer (103), Warlock (147)
//  if cardtype in [8,52,59,65,87,91,93,94,103,147] then Signal('Sound\Play\TriggerAttackUp');

{  eff:=cardInfo[cardtype].soundEffect;
  if eff<>'' then Signal('Sound\Play\'+eff);}
 end;
 finally
  UnlockCards;
 end;
 except on e:Exception do ForceLogMessage('Error in UO.CA: '+ExceptionMsg(e)); end;
 {$endif}
 {$endif}
end;

{$IFNDEF server}
procedure ClearCombatLog;
var
 q:integer;
begin
 for q:=0 to 31 do mesblock.messages[q].numItems:=0;
 mesblock.nummes:=0;
 mesblock.totalLines:=0;
 MessageScrollBar.visible:=false;
// MessageScrollBar.visible:=true;
 MessageScrollBar.max:=0;
 MessageScrollBar.value:=0;
 MessageScrollBar.pagesize:=16*logLineHeight;
end;

function TranslatedFile(fname:string):string;
begin
 result:='Campaign\'+langBaseDir+'\'+fname;
 if MyFileExists(result) then exit;
 result:='Campaign\Eng\'+fname;
end;
{$ENDIF}

procedure PrepareCombat;
var q,w:integer;
begin
 {$ifndef server}
 ClearCombatLog;
 fillchar(signinfo,sizeof(signinfo),0);
// SkipButton.enabled:=duel.curplayer=1;
 turnisfinished:=false;
 suspendedDelayTime:=0;
 attackphase:=false;
 castedcard.card:=0;
 lastclickbutton:=0;
 curActivatedCard:=0;
 canendturn:=true;
 dragforced:=false;
 dragmode:=false;
 fillchar(gamelogic[0].aiinfo,sizeof(gamelogic[0].aiinfo),0);
 for q:=1 to 2 do
 for w:=1 to 6 do slots[q,w]:=0;
 LogicInfo.AddAction(-1);
 combatchatrequired:=(gamelogic[0].playersinfo[2].control<0);
 if gamelogic[0].playersinfo[2].isbot then combatchatrequired:=false;
 chatreceiver:='';
 ucombat.chatEBox.text:='';
 if chatTarget<>'' then begin
  combatchatrequired:=true;
  chatreceiver:=chatTarget;
  ucombat.chatEBox.realtext:=chatBox.realText;
 end;
 {$endif}
end;

procedure forcelogmessage(s:string);
begin
 myservis.forcelogmessage(s);
end;

// Наркоманский код, однозначно!
procedure tsigninfo.processsign(num:integer;processnext:boolean=true);
var t:int64;
 q:integer;
begin
 {$ifndef server}
 try
 LockLogic.Enter;
 try
 if num<=numsigns then
 begin
  t:=MyTickCount;
  if (t-signs[num].starttime>2500) then
  begin

   dec(numsigns);
   for q:=num to numsigns do
    signs[q]:=signs[q+1];

   processsign(num);
  end else
  with signs[num] do
  begin
   curX:=startX;
   curY:=startY+movesign*(t-signs[num].starttime) div 600; // Не править эту строчку не позвав Эстарха, синхронно надо править горизонтальный автосдвиг цифр
   if processnext then
   processsign(num+1);
  end;
 end;
 finally
  LockLogic.Leave;
 end;
 except
  on e:exception do LogMessage('Error in UO.PS: '+ExceptionMsg(e));
 end;
 {$endif}
end;

procedure tsigninfo.AddSign(player,item,value:integer;delayType:integer=0);
// item=num2:
//  0 player's life
// -1 player's spell power
// -2 player's mana
// +11 -  +16 attack

var q,w,e,r,t,n,x,y,delay:integer;
begin
 {$ifndef server}
 {$ifndef aitesting}
 try
 lockLogic.Enter;
 try
 if (gamelogic[0].AIInfo.Emulation=false)and(value<>0) then begin
  delay:=0;
  case delayType of
   1:delay:=round(animationSpeed*0.8);
  end;

  if (item=0)and(value<>0) then begin
   lastdamagedplayer:=player;
   lastdamagetime:=MyTickCount+delay;
   lastdamagevalue:=value;
  end;

  if numsigns<high(signs) then inc(numsigns);

  signs[numsigns].linkedpl:=player;
  signs[numsigns].linkedcreature:=item;
  inc(lastSignID);
  signs[numsigns].UID:=lastSignID;
  if signs[numsigns].linkedcreature>10 then
   dec(signs[numsigns].linkedcreature,10);

  signs[numsigns].starttime:=MyTickCount+delay; // BUG

  signs[numsigns].movesign:=round(-10*screenScaleY);
  if item=0 then
   signs[numsigns].movesign:=round(-13*screenScaleY);
  if item<0 then
   signs[numsigns].movesign:=signs[numsigns].movesign*8 div 10;
{  if fastsign then
   signs[numsigns].movesign:=signs[numsigns].movesign*2;}
  if item>0 then signs[numsigns].movesign:=signs[numsigns].movesign*11 div 10;
  if value>0 then
  begin
   signs[numsigns].signcolor:=$FF00EE00;
   signs[numsigns].signstr:='+'+inttostr(value);
  end else
  begin
   signs[numsigns].signcolor:=$FFFF3131;
   signs[numsigns].signstr:=inttostr(value);
  end;
  if item>10 then
  begin
   // Not tamplier or warlock ability
   if (attackphase)or(mainduel.actingcreature=0)or(not(mainduel.players[mainduel.actingcreature div 10].creatures[mainduel.actingcreature mod 10].cardnum in [19,147])) then
//   if (attackphase)or(not(mainduel.players[mainduel.actingcreature div 10].creatures[mainduel.actingcreature mod 10].cardnum in [19,147])) then
    Signal('Sound\Play\TriggerAttackUp');
   // изменение атаки кричи в бою
   signs[numsigns].startX:=creaturepos(player,item-10).X-round((32+byte(wideScreen)*3)*screenScaleX);
   signs[numsigns].starty:=creaturepos(player,item-10).Y+round(36*screenScaleY);
   signs[numsigns].curX:=signs[numsigns].startX;
   signs[numsigns].curY:=signs[numsigns].startY;
   signs[numsigns].font:=signFont1;
   for q:=1 to 16 do if numsigns-q>0 then
   begin
    if (abs(signs[numsigns-q].curY-signs[numsigns].cury)<round(12*screenScaleY))and(signs[numsigns-q].curx=signs[numsigns].curX) then
    begin
     processsign(numsigns-q,false);
     inc(signs[numsigns].startX,6+length(signs[numsigns-q].signstr)*round(8*screenscaleX));
     signs[numsigns].curX:=signs[numsigns].startX;
     signs[numsigns].startY:=signs[numsigns-q].curY+signs[numsigns].movesign*delay div 600;
    end;
   end;
  end else
  if item>0 then
  begin
   // изменение жизни кричи в бою
   signs[numsigns].startX:=creaturepos(player,item).X+round((32+byte(widescreen)*3)*screenScaleX);
   signs[numsigns].starty:=creaturepos(player,item).Y+round(36*screenScaleY);
   signs[numsigns].curX:=signs[numsigns].startX;
   signs[numsigns].curY:=signs[numsigns].startY;
   signs[numsigns].font:=signFont1;
   if value<0 then
     DelayedSignal('COMBATEFF\DAMAGED',delay,player*10+item+abs(value)*256);
   repeat
    w:=0;
    for q:=1 to 16 do if numsigns-q>0 then
    begin
     if (abs(signs[numsigns-q].curY-signs[numsigns].cury)<round(12*screenScaleY))and(signs[numsigns-q].curx=signs[numsigns].curX) then
     begin
      processsign(numsigns-q,false);
      dec(signs[numsigns].startX,6+length(signs[numsigns-q].signstr)*round(8*screenscaleX));
      signs[numsigns].curX:=signs[numsigns].startX;
      signs[numsigns].startY:=signs[numsigns-q].starty+signs[numsigns].movesign*(signs[numsigns].starttime-signs[numsigns-q].starttime) div 600;
      w:=1;
     end;
    end;
   until w=0;
  end else
  if item=0 then begin
   // изменение жизни игрока
{   if abs(value)>=10 then
    signs[numsigns].startX:=lifestringpos(num1).x-round(screenScaleX*6)
   else}
   signs[numsigns].startX:=lifestringpos(player).x;
   signs[numsigns].starty:=lifestringpos(player).y-round(screenScaleY*25);
   signs[numsigns].curX:=signs[numsigns].startX;
   signs[numsigns].curY:=signs[numsigns].startY;
   signs[numsigns].font:=signFont2;
   for q:=1 to 16 do if numsigns-q>0 then begin
    if (abs(signs[numsigns-q].curY-signs[numsigns].starty)<round(10*screenScaleY))and(signs[numsigns-q].curx=signs[numsigns].curx) then
     inc(signs[numsigns].startX,30);
   end;
   // Эффект
   if value>0 then EFF_PlayerEffect(player,plrEffHeal,value)
    else EFF_PlayerEffect(player,plrEffDamage,-value);
  end else
  if item=-1 then
  begin
   signs[numsigns].startX:=spellpowerstringpos(player).x-round(screenScaleX*6);
   signs[numsigns].startY:=spellpowerstringpos(player).y-round(screenScaleY*22);
   signs[numsigns].font:=signFont2;
  end;
  if item=-2 then
  begin
   signs[numsigns].startX:=manastringpos(player).x-round(screenScaleX*6);
   signs[numsigns].startY:=manastringpos(player).y-round(screenScaleY*22);
   signs[numsigns].font:=signFont2;
  end;
 end;
 finally
  LockLogic.Leave;
 end;
 except
  on e:exception do LogMessage('Error in UO.AS: '+ExceptionMsg(e));
 end;
 {$endif}
 {$endif}
end;

function ConstructMessage(var m:tMessage;s:string;maxwidth:integer=900;tag:integer=0;sender:string=''):string;
var q,w,e,r,t:integer;
    ss,ss2:string;
begin
 {$ifndef server}
 try
// s:=s+' ';
 s:=translate(s);

 m.numItems:=1;
 m.msgtext:=s;
 m.mesItems[m.numItems].startpos:=0;
 m.mesItems[m.numItems].s:='';
 m.mesItems[m.numItems].cardnum:=tag;
 m.mesItems[m.numItems].endpos:=m.mesItems[m.numItems].startpos+painter.TextWidth(logChatFont,m.mesItems[m.numItems].s);
 m.sender:=sender;

 repeat
  while (s<>'')and(s[1]=' ') do s:=copy(s,2,255);
  if sender='' then
  for w:=numcards downto mincard do //if {(maxwidth<900)or}(not(w in [0,152]))and((w<=224)or(w>48+224)) then
  begin
   e:=0;
   for r:=0 to 5 do
   begin
    ss:=cardinfo[w].translatednames[r];
    if uppercase(copy(s,1,length(ss)))=uppercase(ss) then
     e:=length(ss);
   end;
   if e>0 then
   begin
    if (copy(s,e+1,1)='s')and(maxwidth=900) then
     inc(e);
    if (e<>length(s))and(not(s[e+1] in [' ','.',')'])) then
     e:=0;
    if e>0 then
    begin
     if m.mesItems[m.numItems].s<>'' then
     begin
      inc(m.numItems);
     end;
     if m.numItems=1 then
      m.mesItems[m.numItems].startpos:=0
     else
     begin
      m.mesItems[m.numItems].startpos:=m.mesitems[m.numItems-1].startpos+
         painter.TextWidth(logChatFont,m.mesItems[m.numItems-1].s+' ')+round(0.44*screenscalex);
      if (m.mesitems[m.numItems].cardnum=0) then
       inc(m.mesItems[m.numItems].startpos,round(0.44*screenscalex));
     end;

//     if (tag=-2)or(tag=0) then
      m.mesItems[m.numItems].cardnum:=w;
//     else
//      m.mesItems[m.numItems].cardnum:=-1;
     m.mesItems[m.numItems].s:=copy(s,1,e);
     m.mesItems[m.numItems].endpos:=m.mesItems[m.numItems].startpos+
        painter.TextWidth(logChatFont,m.mesItems[m.numItems].s);

 {    inc(m.numItems);
     m.mesItems[m.numItems].startpos:=m.mesItems[m.numItems-1].endpos;
     m.mesItems[m.numItems].s:='';
     m.mesItems[m.numItems].cardnum:=0;
     m.mesItems[m.numItems].endpos:=m.mesItems[m.numItems].startpos;}
     s:=copy(s,e+1,255);
     break;
    end;
   end;
  end;
  while (s<>'')and(s[1]=' ') do s:=copy(s,2,255);

  q:=Pos(' ',s);
  if q>0 then
  begin
   ss:=copy(s,1,q-1);
   s:=copy(s,q+1,255)
  end else
  begin
   ss:=s;
   s:='';
  end;
  if ss<>'' then
  begin
   if m.mesItems[m.numItems].s<>'' then
   begin
    inc(m.numItems);
   end;
   m.mesItems[m.numItems].s:=ss;
   if (ss[1]='.')or(ss[1]=')') then
    ss2:=''
   else
    ss2:=' ';
   if m.numItems=1 then
    m.mesItems[m.numItems].startpos:=0
   else
    m.mesitems[m.numItems].startpos:=m.mesitems[m.numItems-1].startpos+
      painter.TextWidth(logChatFont,m.mesItems[m.numItems-1].s+ss2)+round(0.44*screenscalex);
   if (m.numItems>1) and (m.mesitems[m.numItems-1].cardnum<>0) then
    inc(m.mesItems[m.numItems].startpos,round(0.44*screenscalex));
   m.mesItems[m.numItems].cardnum:=tag;
   m.mesItems[m.numItems].endpos:=m.mesItems[m.numItems].startpos+
     painter.TextWidth(logChatFont,m.mesItems[m.numItems].s);
  end;
 until (q=0)or(m.mesItems[m.numItems].endpos>maxwidth);
 if m.mesItems[m.numItems].endpos>maxwidth then
 begin
  while (m.numitems>1)and((m.mesItems[m.numItems-1].endpos>painter.TextWidth(logChatFont,m.mesItems[m.numItems].s+s))or
    (m.mesItems[m.numItems].endpos>maxwidth)) do
  begin
   s:=m.mesItems[m.numItems].s+' '+s;
   dec(m.numItems);
  end;
  result:=s;
  exit;
 end;
 if m.mesItems[m.numItems].s='' then dec(m.numItems);
 except on e:Exception do ForceLogMessage('Error in UO.CM: '+ExceptionMsg(e)); end;
 {$endif}
end;

procedure ShowMes(mes:string;tag:integer=0;firstlaunch:boolean=true;sender:string='';instant:boolean=false);
var q,w,e,r,t,y,visibleLines:integer;
    needscrollchange:boolean;
    oldscrollpos,oldscrollsize:integer;
    adds:string;
    s:string;

begin
 {$ifndef server}
 {$ifndef aitesting}
 try
 if gamelogic[0].aiinfo.emulation then exit;
 if (tag=-15)and(firstlaunch) then
  Signal('Sound\Play\PrivateMsg');
 mes:=translate(mes);
 forceLogMessage('Show message: "'+mes+'"');
 {$IFDEF local}
 forcelogmessage('mesblock.nummes='+inttostr(mesblock.nummes));
 forcelogmessage('mesblock.totalLines='+inttostr(mesblock.totalLines));
 {$ENDIF}
 try
  LockLogic.Enter;
  curmes:=0;
  if mes<>'' then
  begin
   inc(mesBlock.totalLines);
   if mesblock.nummes=31 then
   begin
    for q:=0 to 30 do mesblock.messages[q]:=mesblock.messages[q+1];
    needscrollchange:=false;
    inc(addcounter);
   end else
   begin
    inc(mesblock.nummes);
    visibleLines:=15-2*byte(ChatAvailable);
    MessageScrollBar.visible:=mesblock.nummes>visibleLines;
    if mesblock.nummes<=visibleLines then
     MessageScrollBar.value:=0;

    if MessageScrollBar.visible then
    begin
    {$IFDEF local}
     forcelogmessage('mesblock event1');
    {$ENDIF}
     MessageScrollBar.max:=(mesblock.nummes)*logLineHeight;
     MessageScrollBar.pagesize:=(visibleLines+1)*logLineHeight;
     oldscrollsize:=MessageScrollBar.max;
     oldscrollpos:=MessageScrollBar.value;
    end;
    mesblock.addy:=-logLineHeight;
    needscrollchange:=MessageScrollBar.visible;
   end;
   adds:=constructMessage(mesblock.messages[mesblock.nummes],mes,
      round((240+byte(widescreen)*65)*ScreenScaleX),tag,sender);
   if mesblock.nummes=1 then
    mesblock.messages[1].colorselect:=false
   else
   if MesBlock.neednewcolorselect then
    mesblock.messages[mesblock.nummes].colorselect:=not(mesblock.messages[mesblock.nummes-1].colorselect)
   else
    mesblock.messages[mesblock.nummes].colorselect:=mesblock.messages[mesblock.nummes-1].colorselect;

   if (mesblock.nummes>1)and(mes[1]='-')and(mes[length(mes)]='-') then
    MesBlock.neednewcolorselect:=true
   else
    MesBlock.neednewcolorselect:=false;
 //  t:=AnimationSpeed-50;
   t:=round(AnimationSpeed*1);
  end else
  begin
   t:=AnimationSpeed div 2;
   needscrollchange:=false;
  end;
 finally
  LockLogic.Leave;
 end;

 if (adds<>'')or(firstlaunch=false) then
  t:=AnimationSpeed div 2;

 ShowMestm:=MyTickCount;
 if firstlaunch then
  AnimationStartTime:=ShowMestm;

 repeat
  try
   LockLogic.Enter;
   w:=MyTickCount-ShowMestm;
   if w>t then w:=t;

   if mes<>'' then begin
//   mesblock.addy:=-21+w div (t div 21);
    mesblock.addy:=-logLineHeight+(w*logLineHeight) div t;
    if mesblock.addy>0 then mesblock.addy:=0;
   end;
   if needscrollchange then
   begin
    MessageScrollBar.Max:=(mesblock.nummes)*logLineHeight+logLineHeight*w div t;
    if oldscrollpos>=oldscrollsize-MessageScrollBar.pagesize-5 then
    MessageScrollBar.Value:=oldscrollpos+logLineHeight*w div t;
   end;
  finally
   LockLogic.leave;
  end;
  sleep(5);
 until (mesblock.addy=0)and(w=t);

 if adds<>'' then
  showmes(adds,tag,false)
 else
 begin
  while MyTickCount<AnimationEndTime do sleep(5);
 end;

 combatmode.mousemove(game.mouseX,game.mousey);
 except on e:Exception do ForceLogMessage('Error in UO.SM: '+ExceptionMsg(e)); end;
 {$endif}
 {$endif}
end;

procedure ActivateCard(num:integer);
var q,w,e,r,t,card,lasttarget,numtargets:integer;
begin
 {$ifndef server}
 try
 if logicinfo.inAction then
  num:=0;
 with mainDuel^ do
 begin
  suspendedDelayTime:=0;
  if num=0 then
  begin
   card:=0;
   hintdelay:=0;
  end else
  if num>0 then
   card:=players[curplayer].handcards[num]
  else
   card:=players[curplayer].creatures[-num].cardnum;
  if (num>0)and(cardinfo[card].life=0)and(cardinfo[card].requiretarget=false) then
  begin
   LogicInfo.AddAction(1,num,0,card);
   // Добавить здесь звук абилки (или не здесь)
   exit;
  end;
  CurActivatedCard:=num;
  if num=0 then
  begin
   for q:=1 to 2 do
   for w:=1 to 6 do slots[q,w]:=0;
  end else
  begin
   numtargets:=0;
   lasttarget:=0;
   for q:=1 to 2 do
   for w:=1 to 6 do
   begin
    if q=curplayer then e:=1 else e:=-1;
    if num>0 then
    begin
     if CanTargetCard(num,w*e) then
     begin
      lasttarget:=w*e;
      inc(numtargets);
      if cardinfo[card].life>0 then
       slots[q,w]:=1
      else
       slots[q,w]:=2;
     end else slots[q,w]:=0
    end;
   end;
  end;
 end;
 except on e:Exception do ForceLogMessage('Error in UO.AC: '+ExceptionMsg(e)); end;
 {$endif}
end;

procedure ActivateAbility(num:integer);
var q,w,e,r,t,card:integer;
begin
 {$ifndef server}
 try
 if logicinfo.inAction=false then
 with mainDuel^ do
 begin
  card:=players[curplayer].creatures[num].cardnum;
  if cardinfo[card].abilityrequiretarget=false then
  begin
   LogicInfo.AddAction(2,num,0);
   exit;
  end;
  CurActivatedCard:=-num;
  for q:=1 to 2 do
  for w:=1 to 6 do
  begin
   if q=curplayer then e:=1 else e:=-1;
   if num>0 then
   begin
    if CanTargetAbility(num,w*e) then
    begin
     if players[q].creatures[w].life=0 then
      slots[q,w]:=1
     else
      slots[q,w]:=2;
    end else slots[q,w]:=0
   end;
  end;
 end;
 except on e:Exception do ForceLogMessage('Error in UO.AA: '+ExceptionMsg(e)); end;
 {$endif}
end;

procedure AutoSave;
{$ifndef server}
var f:file of tduelsave;
{$endif}
begin
 {$ifndef server}
 repeat
  try
   assign(f,'saves\AutoSave.sav');
   rewrite(f);
   duelsave.importData;
   write(f,duelsave);
   close(f);
   break;
  except
   ShowMes('Error in disk operation');
  end;
 until false;
 {$endif}
end;

{$IFNDEF SERVER}
procedure AdjustCardsPos(player:integer);
 var
  i:integer;
  p:TPoint;
  many:boolean;
 begin
  try
  SetWaitFactor;
  many:=handCards[player,8]<>nil;
  for i:=1 to 8 do begin
   if handCards[player,i]=nil then continue;
//   if handCards[player,i].x.IsAnimating then continue;

   if many then p:=pressedcardpos(player,i)
    else p:=cardpos(player,i);
//   if handCards[player,i].x.FinalValue<>p.x then
   handCards[player,i].x.Animate(p.x,animationSpeed+10,spline1);
  end;
  except on e:Exception do ForceLogMessage('Error in UO.ACP: '+ExceptionMsg(e)); end;
 end;

// Извлекает карту из руки игрока, оставшиеся карты сдвигаются как надо
function ExtractCardFromHand(player,index:integer):TGameCard;
var
 i:integer;
begin
 try
 result:=handCards[player,index];
 ASSERT(result<>nil);
 for i:=index to 8 do begin
  handCards[player,i]:=handCards[player,i+1];
 end;
 handCards[player,9]:=nil;
 AdjustCardsPos(player);
 except on e:Exception do ForceLogMessage('Error in UO.ECFH: '+ExceptionMsg(e)); end;
end;

procedure EFF_AbilityUsed(player,card,target:integer;afterMsg:boolean);
begin
 try
 if afterMsg then begin
  // Урон абилкой
  // Goblin Pyromancer (2), Dragon(15), Forest Sprite (16), Elven Lord (37), Elven Archer (38),
  // Vampire Mystic (54), Soul Hunter(56), Bastion of Order (64), Vampire Priest (78)
  // Fire Elemental (83), Mummy (99), Ghoul (104),
  // Fire Drake (107), Gluttonous Zombie (116), Greater Demon (148)
  if card in [2,15,16,37,38,54,56,64,78,83,99,104,107,116,148] then Signal('Sound\Play\TriggerDamage');

  // Faerie Mage (40),
  if card in [40] then Signal('Sound\Play\TriggerDamage');

 end else begin
  // Урон абилкой
  // Vampire Elder (57), Orc Shaman (62), Phoenix (131), Balance Keeper (121),
  if card in [57,62,121,131] then Signal('Sound\Play\TriggerDamage');

  // Убивающая абилка
  // Adept of Darkness (49), Banshee 79, Cultist (101), Glory Seeker (90)
  if card in [49,79,90,101] then
  begin
   Signal('Sound\Play\SpellDestroy');
   if card=101 then
    dontPlayPowerUp:=MyTickCount+2000;
   end;
  // нужна барабанная дробь
  // Zealot (143), Orc Trooper (5), Elven Hero (144), Nightmare Horror(162)
  if card in [5,143,144,162] then Signal('Sound\Play\AbilityAggressive');

  // Нейтральная абилка
  // Templar (19), Insanian Wizard (61), Vampire Priest (78),
  // Harbringer (117), Familiar (140), Cursed Soul (146), warlock 147, Energy mage 158, Elf Summoner 160
  if card in [19,61,78,117,140,146,147,158,160] then Signal('Sound\Play\AbilityNeutral');

  // Gryphon (113)
//  if card in [113] then Signal('Sound\Play\ReturnCreature');

  // Позитивная абилка
  // Leprechaun (31),
  // Archivist (43), Witch Doctor (71),
  // Preacher (92), Ascetic (133), Monk (132)
  if card in [31,43,71,{92,}132] then
//  Signal('Sound\Play\AbilityPositive');
   Signal('Sound\Play\PositiveEffect');

  // Faerie Mage (40), Harpy (81), Dryad (34), Ancient Zubr (41),
  // Lazy Ogre (69), Prophet (110), Ascetic 133
  if card in [34,40,41,69,81,110,133] then Signal('Sound\Play\PositiveEffect');
 end;
  except
   on e:exception do ForceLogMessage('Error in EFF.AU: '+ExceptionMsg(e));
  end;
end;

procedure EFF_ManaStorm;
begin
// manaStorm1.alpha.Animate(0,100,spline0)
end;

procedure EFF_AddManaStorm;
var
 c:TGameCard;
 p:TPoint;
begin
 try
 Lockcards;
 p:=cardPos(2,1,1);
 c:=TGameCard.Create(p.X,p.y-100,0,0,0,0,2,'Combat');
 c.z.Assign(HandCardZ);
 HandCards[2,1]:=c;
 c.y.Animate(p.y,200,spline2);
 AdjustCardsPos(2);
 Unlockcards;
  except
   on e:exception do ForceLogMessage('Error in AMS: '+ExceptionMsg(e));
  end;
end;

procedure EFF_AddHandCard(player,card:integer;cardGiver:integer=0);
 var
  i,n,d:integer;
  c:TGameCard;
  p,p2:TPoint;
 begin
  try
  SetWaitFactor;
  LockCards;
  try
  PutMsg(Format('AddHandCard %d %d %d',[player,card,cardGiver]));
  // 1. Create new card and add it to the end of hand
  n:=8;
  while (n>1) and (handCards[player,n-1]=nil) do dec(n);
//  if n>=8 then p:=pressedcardpos(player,8) else
  p:=cardPos(player,n,1);
  if player=2 then card:=0;
  with mainDuel^ do
   c:=TGameCard.Create(p.x+800,p.y,card,GetCost(player,card),cardinfo[card].damage,cardinfo[card].life,player,'Combat');

  if cardGiver=0 then begin
   // Карта пришла сама-собой
   c.z.Assign(HandCardZ);
   c.x.Animate(p.x,animationSpeed,spline2);
   Signal('Sound\Play\NewCard');
  end else begin
   // Карту дала крича
   SetWaitFactor(1.6);
   d:=round(AnimationSpeed*1.4);
   p2:=CreaturePos(cardGiver div 10,cardGiver mod 10);
   c.x.Assign(p2.x);
   c.y.Assign(p2.y);
   c.MoveTo(p.x,p.y,d,cmmFlyToHand);
   TGiveCardEffect.Create(cardGiver,c);
   Signal('Sound\Play\NewCardGiven');
  end;
  HandCards[player,n]:=c;
  // 2. If too many cards - remove 1-st one
  if n=8 then begin
   c:=ExtractCardFromHand(player,1);
   if player=1 then d:=200 else d:=-200;
    c.y.Animate(c.y.Value+d,animationSpeed,spline2rev);
   c.alpha.Animate(0,animationSpeed,spline0);
   c.DeleteAfter(animationSpeed);
   Signal('Sound\Play\CardLost');
  end else
   AdjustCardsPos(player);
  finally
   UnlockCards;
  end;
  except
   on e:exception do ForceLogMessage('Error in AHC: '+ExceptionMsg(e));
  end;
 end;

// Удаляет карту из руки, помещая её в заданное место:
// target=1..6 - слот существ (свой, нижний ряд)
// target=-1..-6 - слот противника (верхний ряд)
// target=0 - пролет по экрану (заклинание без цели)
// target=9 - просто удаляет (потеря карты из руки)
// target=-9 - сакрифайс: карта превращается в ману
procedure HandCardAction(player,index,target:integer;card:integer=0);
 var
  c:TGameCard;
  p:TPoint;
  d,t:integer;
 begin
  try
  SetWaitFactor;
  LockCards;
  try
  PutMsg('HandCardAction '+inttostr(player)+' '+inttostr(index)+' '+inttostr(target)+' '+inttostr(card));
  c:=ExtractCardFromHand(player,index);
  c.available:=false;
  c.inactive:=true;
  c.cost:=cardInfo[c.cardnum].cost;
  // Summoned creature or targetted spell
  if abs(target) in [1..6] then begin
   if target<0 then begin
    target:=abs(target); player:=3-player;
   end;
   if (creatures[player,target]<>nil) and (card=0) then begin
    // Призыв существа поверх другого существа (которое удаляется)
    creatures[player,target].z.Assign(-0.01);
    creatures[player,target].DeleteAfter(AnimationSpeed);
   end;
   p:=creaturepos(player,target);
   if card>0 then begin
    if dragforced=false then
     t:=AnimationSpeed
    else
     t:=AnimationSpeed div 2;
    c.MoveTo(p.x,p.Y,t,cmmTargetedSpell,not(dragforced));
    c.DeleteAfter(t);
    if dragforced=false then
     TTargetedSpellEffect.Create(c,animationSpeed);
   end else begin
    // summon creature
    if dragforced=false then
     t:=AnimationSpeed
    else
     t:=AnimationSpeed div 3;
    c.MoveTo(p.x,p.Y,t,cmmSummonCreature,not(dragforced));
    Signal('Sound\Play\SummonCreature');
    creatures[player,target]:=c;
    if (cardinfo[c.cardnum].skiplandingeffect=false) then begin
     DelayedSignal('COMBATEFF\SUMMONED',AnimationSpeed-50,player*10+target);
     if player=2 then
      SetWaitFactor(2)
     else
      SetWaitFactor(1.5);
    end else
     LogMessage('Landing skipped');
   end;
  end;
  // Casted spell
  case target of
    0:begin
       // Non-targetted spell
       c.MoveTo(0,0,AnimationSpeed,cmmCastSpell);
       c.DeleteAfter(round(animationSpeed*1.3));
      end;
   9:begin
       // Just lost the card
       d:=round(200*screenScaleY);
       if player=2 then d:=-d;
       c.MoveTo(c.x.intvalue,c.y.intvalue+d,animationSpeed,cmmDiscard);
       c.DeleteAfter(animationSpeed);
      end;
   -9:begin
       // Sacrifice
       c.MoveTo(0,0,AnimationSpeed,cmmCastSpell);
       c.DeleteAfter(animationSpeed);
      end;
  end;
  finally
   UnlockCards;
  end;
  except on e:Exception do ForceLogMessage('Error in UO.HCA: '+ExceptionMsg(e)); end;
 end;

procedure EFF_CastSpell(player,index,target,card:integer);
 var
  st:string;
  delay:integer;
 begin
  try
  HandCardAction(player,index,target,card);
  st:=cardInfo[card].soundEffect;
  if st<>'' then begin
    delay:=0;
    if target<>0 then delay:=round(animationSpeed*0.9);
    DelayedSignal('Sound\Play\'+st,delay,0);
  end;
  except
   on e:exception do ForceLogMessage('Error in EFF_CS: '+ExceptionMsg(e));
  end;
 end;

procedure EFF_PlaceCreature(player,index,target:integer);
 var
  c,old:TGameCard;
  p:TPoint;
 begin
  try
  if index=0 then begin
   if creatures[player,target]<>nil then begin
    // карта уже есть - обновить
    creatures[player,target].attack:=mainDuel.getAttack(player,target);
    creatures[player,target].life:=mainDuel.players[player].creatures[target].life;
    exit;
   end;
   EFF_CreatureReplaced(player,target);
  end else
   HandCardAction(player,index,target);
  except
   on e:exception do ForceLogMessage('Error in EFF_PC: '+ExceptionMsg(e));
  end;
 end;

procedure EFF_CreatureReplaced(player,index:integer);
 var
  c,old:TGameCard;
  p:TPoint;
 begin
  try
  SetWaitFactor;
  LockCards;
  try
   PutMsg('CreatureReplaced '+IntToStr(player)+' '+inttoStr(index));
   if cardinfo[mainduel.players[player].creatures[index].cardnum].isVampire then
    Signal('Sound\Play\SpellNeutral');
   p:=creaturepos(player,index);
   old:=creatures[player,index];
   if old<>nil then begin
    old.alpha.Animate(0,round(AnimationSpeed*0.6),spline0);
    old.DeleteAfter(AnimationSpeed);
   end;
   with mainDuel^.players[player].creatures[index] do
    c:=TGameCard.Create(p.x,p.y,cardnum,cardinfo[cardNum].cost,
        mainDuel.GetAttack(player,index),life,player,'Combat');
   creatures[player,index]:=c;
   c.alpha.Assign(0);
   c.alpha.Animate(1,round(animationSpeed*0.6),spline0,animationSpeed div 4);
  finally
   UnlockCards;
  end;
  except
   on e:exception do ForceLogMessage('Error in EFF_CR: '+ExceptionMsg(e));
  end;
 end;

procedure EFF_ReplaceHandCard(player,index,newCard:integer);
 begin

 end;

procedure EFF_ReturnCreatureToHand(player,index,handPlayer:integer);
 var
  obj:TGameCard;
  i,n:integer;
  p:TPoint;
 begin
  try
  SetWaitFactor;
  LockCards;
  try
  obj:=creatures[player,index];
  creatures[player,index]:=nil;
  n:=1;
  for i:=1 to 8 do
   if handCards[handPlayer,i]=nil then begin
    n:=i; break;
   end;
  if n=8 then begin
   EFF_LoseHandCard(handPlayer,1);
   dec(n);
  end;
  handCards[handPlayer,n]:=obj;
  p:=CardPos(handPlayer,n);
  obj.MoveTo(p.x,p.y,animationSpeed,cmmReturn);
  if handPlayer=2 then obj.cardnum:=0;
  AdjustCardsPos(handPlayer);
  finally
   UnlockCards;
  end;
  except
   on e:exception do ForceLogMessage('Error in EFF_RCTH: '+ExceptionMsg(e));
  end;
 end;

procedure EFF_RemoveManaStorm;
begin
 EFF_CastSpell(2,1,0,-3);
end;

procedure EFF_LoseHandCard(player,index:integer);
 begin
  HandCardAction(player,index,9);
 end;

procedure EFF_LoseAllCards(player:integer);
 var
  i,n:integer;
 begin
  try
  SetWaitFactor;
  n:=0;
  for i:=1 to 8 do
   if handCards[player,i]<>nil then
    inc(n);
  for i:=1 to n do
   EFF_LoseHandCard(player,1);
  except
   on e:exception do ForceLogMessage('Error in EFF_LAC: '+ExceptionMsg(e));
  end;
 end;

procedure EFF_DestroyCreature(player,index:integer);
 var
  obj:TGameCard;
  mf:integer;
 begin
  try
  mf:=44100+random(5000)-random(5000);
  if mainduel.ActingSpell in [60,130,145] then
   Signal('Sound\Play\CreatureSpellDie')
    else
   Signal(Format('Sound\Play\CreatureDie,F=%d',[mf,400]));
  SetWaitFactor;
  LockCards;
  try
   obj:=creatures[player,index];
//   ForceLogMessage('Destroy creature '+Format('%d %d',[player,index]));
   ASSERT(obj<>nil);
   creatures[player,index]:=nil;
   obj.alpha.Animate(0,AnimationSpeed,spline0);
   obj.DeleteAfter(AnimationSpeed);
  finally
   UnlockCards;
  end;
  except
   on e:exception do ForceLogMessage('Error in EFF_DC: '+ExceptionMsg(e));
  end;
 end;

procedure EFF_CreatureAttack(player,index:integer);
 begin
  try
  if attackphase=false then
   HighlightCreature(player,index);
  SetWaitFactor(1.4);
  LockCards;
  try
   CreatureAttacks(player,index);
  finally
   UnlockCards;
  end;
  except
   on e:exception do ForceLogMessage('Error in EFF_CA: '+ExceptionMsg(e));
  end;
 end;

procedure EFF_MoveCreatureToSlot(player,index,newPlayer,newIndex:integer;mode:integer);
 var
  obj,old:TGameCard;
  p:TPoint;
  mt:integer;
 begin
  try
  SetWaitFactor;
  LockCards;
  try
   obj:=creatures[player,index];
   ASSERT(obj<>nil);
   p:=creaturePos(newPlayer,newIndex);
   case mode of
    1:begin // перенос с удалением
     obj.MoveTo(p.x,p.y,animationSpeed,cmmSummonCreature);
     Signal('Sound\Play\SummonCreature');
     creatures[player,index]:=nil;
     creatures[newplayer,newindex].Free;
     creatures[newplayer,newIndex]:=obj;
    end;
    2:begin // обмен позициями
     Signal('Sound\Play\SwapCards');
     old:=creatures[newplayer,newIndex];
     creatures[player,index]:=old;
     if old<>nil then begin
      mt:=animationSpeed div 3;
      old.x.Animate(creaturePos(player,index).X,animationSpeed,spline1);
      old.z.Assign(0.1);
      old.z.Animate(0,1,spline0,animationSpeed);
      old.scale.Animate(1.1,mt,spline2);
      old.scale.Animate(1.0,mt,spline2rev,AnimationSpeed-mt);
     end;
     obj.MoveTo(p.x,p.y,animationSpeed,cmmSummonCreature);
     creatures[newplayer,newIndex]:=obj;
    end;
    3:begin // перенос туда-обратно
     if (index=newIndex) and (player=newPlayer) then begin
      // Перенос на себя - особый случай
      CreatureAct(player,index,true);
     end else begin
      Signal('Sound\Play\AbilityTarget');
      SetWaitFactor(1.6); // более продолжительная анимация
      obj.x.Animate(p.X,animationSpeed,spline2rev);
      obj.x.Animate(creaturePos(player,index).x,animationSpeed div 2,spline2,animationSpeed);
      obj.y.Animate(p.Y,animationSpeed,spline2rev);
      obj.y.Animate(creaturePos(player,index).y,animationSpeed div 2,spline2,animationSpeed);
      mt:=animationSpeed div 4;
      obj.z.Animate(ActingCreatureZ,mt,spline0);
      obj.z.Animate(0,mt,spline0,animationSpeed+animationSpeed div 2-mt);
      obj.scale.Animate(1.1,mt,spline0);
      obj.scale.Animate(1,mt,spline0,animationSpeed+animationSpeed div 2-mt);
     end;
    end;
   end;
  finally
   UnlockCards;
  end;
  except
   on e:exception do ForceLogMessage('Error in EFF_MCTS: '+ExceptionMsg(e));
  end;
 end;

procedure EFF_PlayerEffect(player:integer;effect:TPlayerEffect;value:integer=0);
 begin
  try
  if (gamelogic[0].AIInfo.Emulation=false) then
    CombatEff.PlayerEffect(player,effect,value);
  except on e:Exception do ForceLogMessage('Error in EFF_PE: '+ExceptionMsg(e)); end;
 end;

{$ELSE}
procedure EFF_ManaStorm;
 begin end;
procedure EFF_AddManaStorm;
 begin end;
procedure EFF_RemoveManaStorm;
 begin end;
procedure EFF_AddHandCard(player,card:integer;cardGiver:integer=0);
 begin end;
procedure EFF_ReturnCreatureToHand(player,index,handPlayer:integer);
 begin end;
procedure EFF_LoseAllCards(player:integer);
 begin end;
procedure EFF_CastSpell(player,index,target,card:integer);
 begin end;
procedure EFF_PlaceCreature(player,index,target:integer);
 begin end;
procedure EFF_ReplaceHandCard(player,index,newCard:integer);
 begin end;
procedure EFF_LoseHandCard(player,index:integer);
 begin end;
procedure EFF_DoCreatureAttack(player,index:integer);
 begin end;
procedure EFF_MoveCreatureToSlot(player,index,newPlayer,newIndex:integer;mode:integer);
 begin end;
procedure EFF_CreatureReplaced(player,index:integer);
 begin end;
procedure EFF_DestroyCreature(player,index:integer);
 begin end;
procedure EFF_CreatureAttack(player,index:integer);
 begin end;
procedure EFF_PlayerEffect(player:integer;effect:TPlayerEffect;value:integer=0);
 begin end;
procedure EFF_AbilityUsed(player,card,target:integer;afterMsg:boolean);
begin end;

{$ENDIF}

function ScaledRect(x1,y1,x2,y2:integer;HD:boolean=true):TRect;
begin
 if widescreen then begin
  if HD then
   result:=Rect(round(x1*screenScaleX*HDMagic),
                round(y1*screenScaleY*HDMagic),
                round(x2*ScreenScaleX*HDMagic),
                round(y2*ScreenScaleY*HDMagic))
  else
   result:=Rect(round(x1*screenScaleX),
                round(y1*screenScaleY),
                round(x2*ScreenScaleX),
                round(y2*ScreenScaleY));
 end else
  result:=Rect(round(x1*screenScaleX),
               round(y1*screenScaleY),
               round(x2*ScreenScaleX),
               round(y2*ScreenScaleY));
end;

begin
end.

