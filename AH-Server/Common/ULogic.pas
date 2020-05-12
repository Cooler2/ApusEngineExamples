// Author: Alexey Stankevich (Apus Software)
unit ULogic;
{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
interface
uses Cnsts,UOutput,UDeck,UCardGens;
type

tcreature=object
 cardnum:smallint;                    // 0 - absent
 life,counter,bonus:smallint;
 new,abilitywas,stunned:boolean;
end;

tplayer=object
 life:smallint;
 spellpower,mana:smallint;
 creatures:array[1..6] of tcreature;
 numdeckcards,numhandcards:shortint;
 handcards:array[1..8] of smallint;
 killcreatures:smallint;
 summoncreatures,castspells:smallint;
 dealdamage,manaspend:smallint;
 thinktime:smallint;                  // in seconds
 localcounter:cardinal;               // used by localrandom function
 lastDamageAmount,lastDamageSource:integer;
 dragonssummoned,elvessummoned,vampireskilled:integer;
// deck:tdueldeck;
 function hasCreatures:integer;
 function hasRitualsofPower:integer;
 function localrandom(max:integer):integer;
end;

tDuel=object
 players:array [1..2] of tplayer;
 delayedeffects:array[1..2,1..6] of shortint;
 curplayer:shortint;
 winner:shortint;
 numaction,turnnumber:shortint;
 turnstartingtime:integer;
 ActingCreature,ActingSpell:smallint;
 wasreplace:boolean;
 CurEff:integer;      // for AI purposes
 DrawFactor:integer;  // for AI purposes
 dueltypenum:shortint;// for AI purposes
 threadnum:shortint;  // for AI purposes. Всегда 0, кроме случаев "АИ против АИ"
 function getcost(pl,card:integer):integer;
 function getabilitycost(pl,creature:integer):integer;
 function enemy:integer; inline;
 function CanAttack(pl,num:integer):boolean;
 function CanUseCard(num:integer):boolean;
 function CanTargetCard(num,target:integer):boolean;
 function CanUseAbility(num:integer):boolean;
 function CanTargetAbility(num,target:integer):boolean;
 function getAttack(pl,cr:integer):integer;
 procedure StartTurn;
 procedure Endturn;
 procedure CreatureDies(pl,num:integer);
 procedure CheckOnDie;
 function DealDamage(side1,num1,side2,num2,damage,damagetype:integer;needmes:boolean;needdelay:boolean=false):integer;
 function MassDamage(pl,num,damage,damagetype,targettype:integer):integer;
 procedure GetSpecificCard(pl,card:integer;source:integer=0;sourceparam:integer=0;shownewcard:boolean=true);
 procedure GetCard(pl:integer;showmessage:boolean=false;source:integer=0;sourceparam:integer=0;shownewcard:boolean=false;showeffect:boolean=true;isreplace:boolean=false);
 procedure LoseCard(pl,num:integer;showmessage:boolean=true);
 procedure LoseRitualOfPower(pl,num:integer);
 procedure CreatureReturns(side,num,pl:integer);
 function AttackAttempt(pl,num:integer;needdelay:boolean=false):boolean;
 procedure CreatureAttacks(pl,num,opp:integer);
 procedure CreatureComes(pl,num:integer;oldslot:integer=0);
 procedure SpellCasted(pl,card,target:integer);
 procedure UseAbility(num,target:integer);
 procedure UseCard(num,target:integer);
 function NeedEndTurn:boolean;
 procedure CheckEndTurn;
 procedure PrepareDuel(dueltype:integer{1/2/3};ResultSignal:string='';thread:shortint=0;firstplayer:shortint=0);
 procedure AddLife(pl,num:integer{$ifndef aitesting};mes:string=''{$endif});
 procedure AddMana(pl,num:integer{$ifndef aitesting};mes:string=''{$endif});
 procedure PlaceCreature(pl,num,card:integer);
 function HealCreature(side1,num1,side2,num2,value:integer;needmes,needcreatureact:boolean):integer;
 procedure Replacecard(num:integer);
 procedure BurstAttack(pl,num,value:integer;permanent:boolean=false;needmes:boolean=false);
 function ChangePower(pl,value:integer;manastorm:boolean=false{$ifndef aitesting};mes:string=''{$endif}):boolean;
 function EffectString(pl,card:integer):string;
 procedure CheckDelayedEffects;
 function Emulation:boolean;inline;
 procedure DuelDelay(time:integer);inline;
 procedure SuspendedDelay(time:integer);inline;
 function PlayerName(n:integer):string;
 function getPlayerHash(pl:integer):integer;
end;

tplayerinfo=object
 Name:String[31];
 Deck,CurDeck:tDeck;
 control:integer;                       // 0-player, else - computer AiPower (1-6) -1 remote player
 FaceNum:integer;
 forcedlife:integer;
 forcedfirst,forcedsecond,skipritual,nopremium,noreplace:boolean;
 isbot:boolean;
 level:smallint;
 fullName:string[63]; // имя с описанием
 {$IFDEF AITESTING}
 handgens:tcardgens;
 creaturegens:tcardgens;
 enemycreaturegens:tcardgens;
 handgensused:tcardgens;
 creaturegensused:tcardgens;
 enemycreaturegensused:tcardgens;
 PairGens:tPairgens;
 PairGensUsed:tPairgens;
 {$ElSE}
 time:integer;
 {$ENDIF}
end;

tAiInfo=object
 combating,thinking:boolean;
 AiPlayer:integer;
 Lossvalue:integer;
 gen1,gen2,gen3,gen4,gen5,gen6:integer;
 function emulation:boolean;inline;
end;

{tChooseCards=object
 list:array[1..50] of integer;
 listsize:integer;
 procedure ConstructList(card:integer; var d:tduel);
end;}

tDuelSave=object
 SaveDuel:tDuel;
 SavePlayersInfo:array[1..2] of tPlayerInfo;
 procedure ImportData(threadnum:integer=0);
 procedure ExportData(threadnum:integer=0);
end;

tAIAction=object
 ActionType:smallint;    //0-end turn, 1-use card, , 2-sacrifice card, 3-use ability, 5-surrender, 6-main menu, 7-timeout, 10-message
 ActionDesc:smallint;
 ActionTarget:smallint;
 DescCard:smallint;
 ActionResult:integer;
end;

tAction=object(tAIAction)
 mes:string[255];
 sender:string[32];
 time:int64;
end;

PAction=^TAction;

tAIUnit=object
 AIduel:tduel;
 DuelHash:integer;
 Previous:integer;
 FirstAction:tAiAction;
 {$ifndef aitesting}
 {$ifndef server}
 AiString:string[127];
 {$endif}
 {$endif}
end;


tgamelogic=object
 Duel:tduel;
 PlayersInfo:array[1..2] of tPlayerInfo;
 AiInfo:tAiInfo;
 AIAction:tAIAction;
 AIUnits:array[1..AIMaxWidth] of tAIUnit;
 AICashe:array[1..AICasheSize] of smallint;
end;

var isonline:boolean;
    {$IFDEF SERVER}
    gamelogic:array[0..numServerthreads] of tgamelogic;
    {$ELSE}
    gamelogic:array[0..numAIthreads-1] of tgamelogic;
    {$ENDIF}
    mainDuel:^TDuel;
    DuelSave:tDuelSave;
    curActivatedCard:smallint;                   // <0 - creature ability
//    optInfo:tOptInfo;

threadvar
    errorstring:string;

implementation
uses
{$IFnDEF SERVER}
  ulogicthread,
{$ENDIF}

  eventman,MyServis,sysutils,UCompAI;



var buf:array[0..10000] of byte;

function tplayer.localrandom(max:integer):integer;
var q:cardinal;
begin
 q:=deckseed;
 deckseed:=localcounter;
 result:=protectedrandom(max);
 localcounter:=deckseed;
 deckseed:=q;
end;

function tplayer.hasCreatures:integer;
var q,w:integer;
begin
 result:=0;
 for q:=1 to 6 do if (creatures[q].life>0)and(creatures[q].cardnum<>0) then inc(result);
end;

function tplayer.hasRitualsofPower:integer;
var q,w:integer;
begin
 result:=0;
 for q:=1 to numhandcards do
 if handcards[q]=-1 then
  inc(result);
end;

procedure tduel.prepareDuel(dueltype:integer{1/2/3};ResultSignal:string='';thread:shortint=0;firstplayer:shortint=0);
var q,w,e,r,n:integer;
    pl:tplayer;
    pli:tplayerinfo;
    b:byte;
    ds:tDuelSave;
begin
{ if isonline=false then
 for q:=1 to 2 do
 for w:=1 to 30 do if cardinfo[playersinfo[q].Deck.cards[w,1]].premiumcard then
 begin
  if w mod 2=0 then
   playersinfo[q].Deck.cards[w,1]:=6
  else
   playersinfo[q].Deck.cards[w,1]:=51;
 end;}
 fillchar(self,sizeof(tduel),0);
 if dueltype=4 then
  dueltype:=1;
 dueltypenum:=dueltype;
 threadnum:=thread;
 turnnumber:=0;
 winner:=0;
 if gamelogic[thread].playersinfo[2].forcedfirst then
  firstplayer:=2
 else if gamelogic[thread].playersinfo[2].forcedsecond then
  firstplayer:=1;

 if firstplayer=0 then
 begin
  curplayer:=1;
  if random(2)=0 then
   curplayer:=2;
 end else
  curplayer:=firstplayer;

 for q:=1 to 2 do
 begin
  gamelogic[thread].playersinfo[q].curdeck:=gamelogic[thread].playersinfo[q].deck;
  if gamelogic[thread].playersinfo[q].forcedlife<>0 then
   players[q].life:=gamelogic[thread].playersinfo[q].forcedlife
  else
   players[q].life:=30;
  players[q].numdeckcards:=gamelogic[thread].playersinfo[q].deck.decksize;
  if players[q].numdeckcards=0 then
   players[q].numdeckcards:=40;
  players[q].numhandcards:=4;
{  if q<>curplayer then
   inc(players[q].numhandcards);}
  players[q].localcounter:=0;
  for w:=1 to players[q].numhandcards do
  begin
   players[q].handcards[w]:=gamelogic[thread].playersinfo[q].curdeck.cards[players[q].numdeckcards];
   inc(players[q].localcounter,players[q].handcards[w]*(players[q].handcards[w]+1));
   if gamelogic[thread].playersinfo[q].deck.name='CMPD#18#' then
    inc(players[q].localcounter,random(1111));
   dec(players[q].numdeckcards);
  end;
  if (q<>curplayer)and(gamelogic[thread].playersinfo[q].skipritual=false) then
  begin
   inc(players[q].numhandcards);
   players[q].handcards[players[q].numhandcards]:=-1;
  end;

  {$ifndef aitesting}
  {$ifndef server}
  if gamelogic[thread].playersinfo[q].isbot=false then
  begin
   gamelogic[thread].playersinfo[q].name:=gamelogic[thread].playersinfo[q].name+'`9';
   if gamelogic[thread].playersinfo[q].fullname='' then
    gamelogic[thread].playersinfo[q].fullname:=gamelogic[thread].playersinfo[q].name;
   gamelogic[thread].playersinfo[q].fullname:=gamelogic[thread].playersinfo[q].fullname+#13;
  end;
  logmessage('name='+gamelogic[thread].playersinfo[q].name);
  logmessage('fullname='+gamelogic[thread].playersinfo[q].fullname);
  {$endif}
  {$endif}
 end;

 if resultsignal<>'' then
 Signal(ResultSignal);
end;

procedure tDuel.CheckDelayedEffects;
var q,w,e,pl:integer;
begin
 for q:=1 to 2 do
 begin
  if q=1 then pl:=3-curplayer else
   pl:=curplayer;
  for w:=1 to 6 do
  begin
   if delayedeffects[pl,w]<>0 then
   begin
    case players[pl].creatures[w].cardnum of
     {Vampire Lord}
     59:if players[pl].creatures[delayedeffects[pl,w] mod 10].cardnum<>0 then
        begin
         burstattack(delayedeffects[pl,w] div 10,delayedeffects[pl,w] mod 10,2,true);
         markcreature(pl,w);
        end;
     {Undead Librarian}
     115:begin
          creatureact(pl,w);
          GetCard(pl,true,115,pl*10+w);
         end;
    end;
    delayedeffects[pl,w]:=0;
   end;
  end;
 end;
end;

procedure tduel.PlaceCreature(pl,num,card:integer);
begin
 players[pl].creatures[num].new:=true;
 players[pl].creatures[num].abilitywas:=false;
 players[pl].creatures[num].cardnum:=card;
 players[pl].creatures[num].counter:=0;
 players[pl].creatures[num].bonus:=0;
 players[pl].creatures[num].life:=cardinfo[card].life;
 if not Emulation then EFF_PlaceCreature(pl,0,num);
end;

function tduel.getcost(pl,card:integer):integer;
var q:integer;
begin
 if (card<mincard)or(card>numcards) then
 begin
  forcelogmessage('Incorrect duel.getcost card='+inttostr(card));
  for q:=1 to players[curplayer].numhandcards do
   forcelogmessage('card'+inttostr(q)+'='+inttostr(players[curplayer].handcards[q]));
 end;
 result:=cardinfo[card].cost;

 {Efreet}
 if cardinfo[card].element=2 then
 for q:=1 to 6 do
 if players[pl].creatures[q].cardnum=141 then
 begin
  dec(result,2);
  if result<0 then
   result:=0;
 end;
end;

function tduel.getabilitycost(pl,creature:integer):integer;
var q:integer;
begin
 if creature>0 then
 begin
  result:=cardinfo[players[pl].creatures[creature].cardnum].abilitycost;
  if result<0 then
   result:=0;
 end else
  result:=2;
end;

procedure tduel.StartTurn;
var q,w,e,pl,num,card:integer;
    tm:int64;
begin
 {$ifndef aitesting}
 turnisfinished:=false;
 if (emulation=false)and(curplayer=1) then
  canendturn:=true;
 {$endif}
 inc(turnnumber);
 numaction:=0;
 pl:=curplayer;
 inc(players[pl].spellpower);
 players[pl].mana:=players[pl].spellpower;
 if gamelogic[threadnum].AiInfo.thinking=false then
 begin
{  if turnnumber=2 then
  begin
   inc(players[pl].mana);
   if emulation=false then
    ShowMes(playername(pl)+' receives 1 mana point as second player');
  end;}
  if turnnumber>=41 then
  begin
   if emulation=false then
    Signal('Sound\Play\TriggerDamage');
   q:=DealDamage(pl,0,pl,0,integer(turnnumber-40){*(turnnumber-40)},-1,false);
   ShowMes(playername(pl)+'^ ^receives %1 damage from exhaustion%%'+inttostr(q));
   checkondie;
   if winner>0 then exit;
  end;
 end;
 wasreplace:=false;
 for q:=1 to 6 do
 begin
  players[pl].creatures[q].abilitywas:=false;
  players[3-pl].creatures[q].new:=false;
 end;

 if (gamelogic[threadnum].playersinfo[curplayer].deck.name='CMPD#18#')and(turnnumber>1) then
 begin
  w:=players[pl].numhandcards;
  players[pl].numhandcards:=0;
  if emulation=false then
   EFF_LoseAllCards(pl);
  ShowMes('Estarh replaces all cards (passive ability)');
  for q:=1 to w do
  begin
   repeat
    e:=players[pl].localrandom(numcards);
   until cardinfo[e].special=false;
   GetSpecificCard(pl,e,0,0,false);
//   GetCard(pl,true);
  end;
 end;

 if turnnumber>1 then
 begin
  if gamelogic[threadnum].AiInfo.thinking=false then
  GetCard(pl);
 end;

 for num:=1 to 6 do
 begin
  card:=players[pl].creatures[num].cardnum;
  case card of
   {Elven Priest}
   39:begin
       DuelDelay(100);
       CreatureAct(pl,num);
       AddMana(pl,1,{$ifndef aitesting}cardinfo[39].name+' ^generates %1 mana for its owner%%1'{$endif});
       SuspendedDelay(300);
      end;
   {Paladin}
   87:begin
       DuelDelay(100);
       MarkCreature(pl,num);
       BurstAttack(pl,num,1,true);
       SuspendedDelay(300);
      end;
   {Elven Sage}
   137:begin
        DuelDelay(100);
        CreatureAct(pl,num);
        GetCard(pl,true,137,pl*10+num);
        SuspendedDelay(300);
       end;
  end;
 end;
 CheckOnDie;

 if emulation=false then
  turnstartingtime:=MyTickCount div 1000;

 {$ifndef aitesting}
 if winner>0 then exit;

 if emulation then exit;
 numaction:=0;

 if gamelogic[threadnum].playersinfo[pl].control>0 then
 begin
  repeat
   tm:=MyTickCount;
//   if AiInfo.combating=false then AIDuel:=duel;
   FindBestAction(gamelogic[threadnum].AIAction);
//   AIAction.ActionType:=0;
   if emulation=false then
   begin
    repeat
     sleep(5);
    until MyTickCount-tm>400;
{   if gamelogic[threadnum].AiAction.ActionType=1 then
    begin
     w:=players[pl].handcards[gamelogic[threadnum].AiAction.ActionDesc];
     if w<>-1 then
     ShowCardInfo(w,gamelogic[threadnum].AiAction.ActionDesc);
    end;
    if gamelogic[threadnum].AiAction.ActionType=2 then
    begin
     w:=players[pl].creatures[gamelogic[threadnum].AiAction.ActionDesc].cardnum;
     ShowCardInfo(w+1000,gamelogic[threadnum].AiAction.ActionDesc);
    end;}
   end;
   case gamelogic[threadnum].AiAction.ActionType of
    1,3:UseCard(gamelogic[threadnum].AiAction.ActionDesc,gamelogic[threadnum].AiAction.ActionTarget);
    2:UseAbility(gamelogic[threadnum].AiAction.ActionDesc,gamelogic[threadnum].AiAction.ActionTarget);
//    3:SacrificeCard(gamelogic[threadnum].AiAction.ActionDesc);
    4:Replacecard(gamelogic[threadnum].AiAction.ActionDesc);
   end;
   if winner>0 then exit;
  until gamelogic[threadnum].AIAction.ActionType=0;
  EndTurn;
 end;

 if (needTutorials and 16=16)and(curplayer=1)and(turnnumber=3) then
 begin
  needTutorials:=needTutorials xor 16;
  tutorialPause:=true;
  Signal('UI\COMBAT\SHOWTUTORIAL2');
 end;
 {$endif}
end;

procedure tduel.Endturn;
var q,w,e:integer;
    nd:boolean;
begin
 if emulation=false then
  inc(players[curplayer].thinktime,(MyTickCount div 1000) - turnstartingtime)
 else
 if (gamelogic[threadnum].AiInfo.AiPlayer=curplayer)and(gamelogic[threadnum].PlayersInfo[gamelogic[threadnum].AiInfo.AiPlayer].control>=3)and(turnnumber in [1,2])and(players[curplayer].mana>0) then
  dec(cureff,2000);
 try
 {$ifndef aitesting}
 if (emulation=false)and(curplayer=1) then
  autosave;
 turnisfinished:=true;
 if emulation=false then
 begin
  ForceLogMessage('EndTurn, hash='+inttostr(getPlayerHash(curplayer)));
  ActivateCard(0);
 end;
 {$endif}

 {Attack}
 if emulation=false then
  attackphase:=true;
 nd:=true;
 for q:=1 to 6 do if players[curplayer].creatures[q].cardnum<>0 then
 begin
  if AttackAttempt(curplayer,q,nd) then
   nd:=false;
  if winner>0 then
   exit;
 end;
 if emulation=false then
  attackphase:=false;

 for q:=1 to 2 do
 for w:=1 to 6 do
 begin
  players[q].creatures[w].bonus:=0;
 end;

 if emulation=false then
  ShowMes('-- ^'+playername(curplayer)+'^ ^ends turn^ --');
 curplayer:=enemy;
 StartTurn;
 except
  on e:Exception do ForceLogMessage('Error in end turn - '+e.Message);
  else ForceLogMessage('Except in end turn');
 end;
end;

procedure tDuel.AddLife(pl,num:integer{$ifndef aitesting};mes:string=''{$endif});
var q,w:integer;
begin
 inc(players[pl].life,num);
 if (players[pl].life>100)and((players[pl].life<900)or(emulation=false)) then
  players[pl].life:=100;

 {$ifndef aitesting}
 signinfo.addsign(pl,0,num);
 if not emulation then
  EFF_PlayerEffect(pl,plrEffHeal,num);
 if mes<>'' then
 begin
  if mes='default' then
   mes:=playername(pl)+'^ ^receives %1 life%%'+inttostr(num);
  if emulation=false then
   ShowMes(mes);
 end;
 {$endif}
end;

procedure tDuel.AddMana(pl,num:integer{$ifndef aitesting};mes:string{$endif});
var q,w:integer;
begin
 inc(players[pl].mana,num);
// signinfo.addsign(pl,0,num);
 {$ifndef aitesting}
 signinfo.AddSign(pl,-2,num);
 if not emulation then
  EFF_PlayerEffect(pl,plrEffGainMana,num);
 if mes<>'' then
 begin
  if mes='default' then
   mes:=playername(pl)+'^ ^receives %1 mana%%'+inttostr(num);
  if emulation=false then
   ShowMes(mes);
 end;
 {$endif}
end;

function tDuel.Enemy:integer;
begin
 Enemy:=3-curplayer;
end;

function tDuel.CanUseCard(num:integer):boolean;
var q,w,e,r,t,n,pl,target:integer;
begin
 result:=true;
 if num>players[curplayer].numhandcards then
 begin
  result:=false;
  exit;
 end;
 n:=players[curplayer].handcards[num];

 {for AI purposes}
 if n=0 then
 begin
  if (gamelogic[threadnum].playersinfo[curplayer].control>=4)and(players[curplayer].mana>=1) then
   result:=true
  else
   result:=false;
  exit;
 end;

 pl:=curplayer;
 if getcost(curplayer,n)>players[curplayer].mana then
 begin
  result:=false;
  if emulation=false then
   ErrorString:='You need %1 or more mana~to play this card.%%'+inttostr(getcost(curplayer,n));
  exit;
 end;
 if cardinfo[n].life>0 then
 begin
  result:=false;
  for target:=1 to 6 do
  if CanTargetCard(num,target) then
   result:=true;
  if (result=false)and(emulation=false) then
   ErrorString:='You need an empty slot~to summon this creature.';
 end else
 begin
  if cardinfo[n].requiretarget then
  begin
   result:=false;
   for target:=-6 to 6 do if CanTargetCard(num,target) then
    result:=true;
   if (result=false)and(emulation=false) then
    ErrorString:='You can''t play %1 because~there are no valid targets.%%'+cardinfo[n].name;
  end;
 end;
end;

function tDuel.CanTargetCard(num,target:integer):boolean;
var n,pl,q:integer;
begin
 n:=players[curplayer].handcards[num];
 if target<0 then pl:=3-curplayer else pl:=curplayer;

 if (cardinfo[n].life>0) then
 begin
  if (target<=0)or(not(players[pl].creatures[abs(target)].cardnum in [0,112{Wisp}])) then
  begin
   result:=false;
   exit;
  end;
 end else
 begin
  if cardinfo[n].requiretarget then
  begin
   if (target=0)or(players[pl].creatures[abs(target)].cardnum=0) then
   begin
    result:=false;
    exit;
   end;
   if ((cardinfo[n].targettype=1)and(target>0))or((cardinfo[n].targettype=2)and(target<0)) then
   begin
    result:=false;
    exit;
   end else
   begin
    {Astral Guard}
    if target<0 then
    begin
     q:=abs(target);
     if ((q>1)and(players[pl].creatures[q-1].cardnum=72))or((q<6)and(players[pl].creatures[q+1].cardnum=72)) then
     begin
      result:=false;
      exit;
     end;
    end;
    {Dark Slaying}
    if (n=51)and(cardinfo[players[pl].creatures[abs(target)].cardnum].cost>cardinfo[51].logicparam) then
    begin
     result:=false;
     exit;
    end;
    {Preachment}
    if (n=29)and(players[3-pl].creatures[abs(target)].cardnum<>0) then
    begin
     result:=false;
     exit;
    end;
    {Guardian Angel}
    if (target<>0)and(players[pl].creatures[abs(target)].cardnum=74) then
    begin
     result:=false;
     exit;
    end;
    {Soul Explosion}
    if (n=46)and(players[3-pl].creatures[abs(target)].cardnum=0) then
    begin
     result:=false;
     exit;
    end;
   end;
  end else if target<>0 then
  begin
   result:=false;
   exit;
  end;
 end;
 result:=true;
end;

function tDuel.getAttack(pl,cr:integer):integer;
var q,w,e,r,t,cn:integer;
begin
 cn:=players[pl].creatures[cr].cardnum;
 r:=cardinfo[cn].damage;
 if r=-1 then r:=players[pl].spellpower;
// if r=-2 then r:=players[pl].numhandcards;

 inc(r,players[pl].creatures[cr].counter);
 inc(r,players[pl].creatures[cr].bonus);

 {Tentacle Demon}
 if (cn=161)and(players[3-pl].creatures[cr].cardnum<>0) then
  inc(r,cardinfo[161].logicparam);

 {Goblin Chieftain}
 if (cr>1)and(players[pl].creatures[cr-1].cardnum=9) then
  inc(r,cardinfo[9].logicparam);
 if (cr<6)and(players[pl].creatures[cr+1].cardnum=9) then
  inc(r,cardinfo[9].logicparam);

 {Warlord}
 for q:=1 to 6 do
 if (q<>cr)and(players[pl].creatures[q].cardnum=23) then
  inc(r,1);

 if r<0 then
 begin
  q:=-r;
  r:=0;
  if players[pl].creatures[cr].bonus>=0 then
   inc(players[pl].creatures[cr].counter,q);
 end;
 result:=r;
end;

function tDuel.EffectString(pl,card:integer):string;
var q,w,e,r,r0,r2,rr,rr2:integer;
    hidden:boolean;
begin
 result:='';
 r0:=0;
 rr:=0;
 if cardinfo[card].autoeffect then
 begin
  r:=cardinfo[card].logicparam;
  hidden:=true;
 end else
 begin
  r:=-1;
  hidden:=false;
  case card of
   {Fire Ball}
   4:begin
      r:=cardinfo[card].logicparam;
      rr:=cardinfo[card].logicparam2;
      hidden:=true;
     end;
   {Chain Lightning}
   14:begin
       r0:=players[pl].spellpower;
       r:=players[pl].spellpower;
      end;
   {Anathema}
   109:begin
        r:=0;
        for q:=1 to 2 do
        for w:=1 to 6 do if players[q].creatures[w].cardnum<>0 then
         inc(r,getattack(q,w));
       end;
   {Void bolt}
   127:begin
        r:=0;
        for q:=1 to 6 do
        if players[pl].creatures[q].cardnum=0 then
         inc(r,cardinfo[127].logicparam);
       end;
   {Final sacrifice}
   138:begin
        r:=players[pl].life div 2;
       end;
  end;
 end;
 if r<>-1 then
 begin
  r2:=r;
  rr2:=rr;
  {druid, vindictive angel}
  if cardinfo[card].effecttoenemycreatures then
  for q:=1 to 6 do
  if players[pl].creatures[q].cardnum in [14,28,96] then
  begin
   inc(r2,r2);
   inc(rr2,rr2);
  end;
  {Elven mage}
  for q:=1 to 6 do
  if players[pl].creatures[q].cardnum=123 then
  begin
   if r0<>0 then
   inc(r0,cardinfo[123].logicparam);
   inc(r2,cardinfo[123].logicparam);
   if rr2<>0 then
    inc(rr2,cardinfo[123].logicparam);
  end;

  if (r2<>r)or(hidden=false) then
  begin
   if (r0>0)and(r0<>r2) then
    result:='(Effect: %1 damage and %2 damage)%%'+inttostr(r0)+'%%'+inttostr(r2)
   else
   if rr2>0 then
    result:='(Effect: %1 damage and %2 damage)%%'+inttostr(r2)+'%%'+inttostr(rr2)
   else
    result:='(Effect: %1 damage)%%'+inttostr(r2)
  end;
 end;
end;

function tDuel.CanUseAbility(num:integer):boolean;
var q,w,e,n,pl,target:integer;
    fcr,acr:integer;
begin
 result:=true;
 pl:=curplayer;

 {Mana Storm}
 if num=0 then
 begin
  result:=(players[pl].spellpower>=2)and(players[pl].mana>=2)and(players[pl].numhandcards=0)and(gamelogic[threadnum].PlayersInfo[pl].control<>1);
  exit;
 end;

 n:=players[curplayer].creatures[num].cardnum;
 if (n=0)or(cardinfo[n].abilitycost=0)or(getabilitycost(pl,num)>players[curplayer].mana)or(players[curplayer].creatures[num].abilitywas) then
 begin
  result:=false;
  exit;
 end;

 {Forest Sprite}
 if (n=16)and(players[pl].creatures[num].new=false) then
 begin
  result:=false;
  exit;
 end;

 {Leprechaun}
 if (n=31) then
 begin
  result:=false;
  if (num>1)and(players[pl].creatures[num-1].cardnum<>0)and(players[pl].creatures[num-1].life<cardinfo[players[pl].creatures[num-1].cardnum].life) then
   result:=true;
  if (num<6)and(players[pl].creatures[num+1].cardnum<>0)and(players[pl].creatures[num+1].life<cardinfo[players[pl].creatures[num+1].cardnum].life) then
   result:=true;
  exit;
 end;

 {Goblin Pyromancer, Tentacle Demon}
 if (n in [2,161])and(players[3-pl].creatures[num].cardnum<>0) then
 begin
  result:=false;
  exit;
 end;

 {Harpy}
 if (n=81)and((players[3-pl].spellpower=0)or(players[3-pl].creatures[num].cardnum<>0)) then
 begin
  result:=false;
  exit;
 end;

 {Harbringer}
 if (n in [117])and(players[pl].numhandcards=0) then
 begin
  result:=false;
  exit;
 end;

 {Card required}
 if (cardinfo[n].abilityrequirecard)and(players[pl].numhandcards=0) then
 begin
  result:=false;
  exit;
 end;

 {Prophet}
 if (n=110)and(players[pl].spellpower=0) then
 begin
  result:=false;
  exit;
 end;

 {Balance Keeper}
 if (n=121)and(players[pl].life>=players[3-pl].life) then
 begin
  result:=false;
  exit;
 end;

 {Zealot}
 if n=143 then
 begin
  w:=0;
  for q:=-1 to 1 do
  if (q<>0)and(q+num>=1)and(q+num<=6)and(players[pl].creatures[q+num].cardnum=0) then
   inc(w);
  if w=0 then
  begin
   result:=false;
   exit;
  end;
 end;

 {Cursed Soul}
 if n=146 then
 begin
  w:=0;
  for q:=-1 to 1 do
  if (q<>0)and(q+num>=1)and(q+num<=6)and(players[pl].creatures[q+num].cardnum<>0)and(players[pl].creatures[q+num].cardnum<>146) then
   inc(w);
  if w=0 then
  begin
   result:=false;
   exit;
  end;
 end;

 {Warlock}
 if (n=147)and(getAttack(pl,num)<cardinfo[147].logicparam) then
 begin
  result:=false;
  exit;
 end;

 if cardinfo[n].abilityrequiretarget then
 begin
  result:=false;
  for target:=-6 to 6 do if CanTargetAbility(num,target) then
   result:=true;
  exit;
 end;
end;

function tDuel.CanTargetAbility(num,target:integer):boolean;
var q,n,pl,t:integer;
begin
 {Mana Storm}
 if num=0 then
 begin
  result:=target=0;
  exit;
 end;

 n:=players[curplayer].creatures[num].cardnum;
 if (cardinfo[n].abilityrequiretarget)xor(target<>0) then
 begin
  result:=false;
  exit;
 end;

 result:=true;

 if target<0 then pl:=3-curplayer else pl:=curplayer;

 if ((cardinfo[n].abilitytargettype=1)and(target>=0))or((cardinfo[n].abilitytargettype=2)and(target<=0)) then
 begin
  result:=false;
  exit;
 end;

 {Crusader,Elven Scout, Devourer, Fire Drake}
 if n in [17,32,103,107] then
 begin
  if players[pl].creatures[abs(target)].cardnum<>0 then
   result:=false;
  exit;
 end;

 {Assault Snake, Elf Summoner}
 if (n in [159,160]) then
 begin
  if (players[pl].creatures[abs(target)].cardnum<>0)or(abs(abs(target)-num)>1) then
   result:=false;
  exit;
 end;

 if (cardinfo[n].abilityrequiretarget)and(players[pl].creatures[abs(target)].cardnum=0) then
 begin
  result:=false;
  exit;
 end;

 {Can not target self}
 {Unholy Monument,Goblin Pyromancer, Elven Archer, Air Elemental, Metamorph, Temple Warrior, Elven Dancer,ErgoDemon,Ghoul}
 if (n in [1,2,38,82,84,88,96,98,100,104])and(num=abs(target))and(pl=curplayer) then
 begin
  result:=false;
  exit;
 end;

 {Insanian Wizard}
 if (n=61)and(players[pl].creatures[abs(target)].cardnum=-2) then
 begin
  result:=false;
  exit;
 end;

 {Fire Elemental}
 if (n=83)and(players[3-pl].creatures[abs(target)].cardnum=0) then
 begin
  result:=false;
  exit;
 end;

 {Glory Seeker}
 if (n=90)and(GetAttack(pl,abs(target))<6) then
 begin
  result:=false;
  exit;
 end;

 {Gluttonous Zombie}
 if (n=116)and(GetAttack(pl,abs(target))>=GetAttack(curplayer,num)) then
 begin
  result:=false;
  exit;
 end;

 {Greater Demon}
 if (n=148)and(abs(num-abs(target))<>1) then
 begin
  result:=false;
  exit;
 end;
end;

procedure tDuel.CreatureDies(pl,num:integer);
var cn,killer,q,qq,w:integer;
begin
 DuelDelay(1);
 cn:=players[pl].creatures[num].cardnum;

 inc(players[curplayer].killcreatures);
 if cardinfo[cn].isVampire then
  inc(players[curplayer].vampireskilled);

 {$ifndef aitesting}
 if emulation=false then
 begin
  EFF_DestroyCreature(pl,num);
  ShowMes(cardinfo[cn].name+' ^dies');
 end;
 {$endif}

 players[pl].creatures[num].cardnum:=0;
 players[pl].creatures[num].life:=0;

 {Unstable Ooze}
 if (cn=85)and(pl=curplayer) then
 begin
  DuelDelay(200);
  AddMana(pl,cardinfo[85].logicparam,{$ifndef aitesting}cardinfo[85].name+' ^generates %1 mana for its owner%%'+inttostr(cardinfo[85].logicparam){$endif});
  SuspendedDelay(300);
 end;

 {Battle Priest}
 if actingspell<>130 then
 begin
  if (players[3-pl].creatures[num].cardnum=8)and(players[3-pl].creatures[num].life>0) then
  begin
   DuelDelay(250);
   BurstAttack(3-pl,num,cardinfo[8].logicparam,true);
   SuspendedDelay(250);
  end;
  if (num>1)and(players[pl].creatures[num-1].cardnum=8)and(players[pl].creatures[num-1].life>0) then
  begin
   DuelDelay(250);
   BurstAttack(pl,num-1,cardinfo[8].logicparam,true);
   SuspendedDelay(250);
  end;
  if (num<6)and(players[pl].creatures[num+1].cardnum=8)and(players[pl].creatures[num+1].life>0) then
  begin
   DuelDelay(250);
   BurstAttack(pl,num+1,cardinfo[8].logicparam,true);
   SuspendedDelay(250);
  end;
 end;

 {Vampire Initiate, Vampire Mystic}
 if ActingCreature>0 then
 begin
  killer:=players[ActingCreature div 10].creatures[ActingCreature mod 10].cardnum;

  {Soul Hunter killed self}
  if (killer=0)and(ActingCreature div 10=pl)and(ActingCreature mod 10=num)and(cn=56) then
   killer:=56;

  case killer of
   47:begin
//       CreatureAct(ActingCreature div 10,ActingCreature mod 10);
       players[ActingCreature div 10].creatures[ActingCreature mod 10].cardnum:=54;
       HealCreature(ActingCreature div 10,ActingCreature mod 10,ActingCreature div 10,ActingCreature mod 10,cardinfo[47].logicparam,false,false);
       CreatureAct(ActingCreature div 10,ActingCreature mod 10);
       if emulation=false then
       begin
        DuelDelay(100);
        EFF_CreatureReplaced(ActingCreature div 10,ActingCreature mod 10);
        ShowMes(cardinfo[47].name+' ^transforms to %1 and heals %2 life to self%%'+cardinfo[54].name+'%%'+inttostr(cardinfo[47].logicparam));
        SuspendedDelay(300);
       end;
      end;
   54:begin
//       CreatureAct(ActingCreature div 10,ActingCreature mod 10);
       players[ActingCreature div 10].creatures[ActingCreature mod 10].cardnum:=57;
       HealCreature(ActingCreature div 10,ActingCreature mod 10,ActingCreature div 10,ActingCreature mod 10,cardinfo[54].logicparam,false,false);
       CreatureAct(ActingCreature div 10,ActingCreature mod 10);
       if emulation=false then
       begin
        DuelDelay(100);
        EFF_CreatureReplaced(ActingCreature div 10,ActingCreature mod 10);
        ShowMes(cardinfo[54].name+' ^transforms to %1 and heals %2 life to self%%'+cardinfo[57].name+'%%'+inttostr(cardinfo[54].logicparam));
        SuspendedDelay(300);
       end;
      end;
      {Soul Hunter}
   56:begin
       DuelDelay(100);
       if players[ActingCreature div 10].creatures[ActingCreature mod 10].cardnum<>0 then
        MarkCreature(ActingCreature div 10,ActingCreature mod 10);
       GetSpecificCard(ActingCreature div 10,cn,56,ActingCreature);
       waitAnimation;
       SuspendedDelay(300);
      end;
   {Devourer}
   103:begin
        DuelDelay(100);
        MarkCreature(ActingCreature div 10,ActingCreature mod 10);
        BurstAttack(ActingCreature div 10,ActingCreature mod 10,cardinfo[103].logicparam,true);
        waitAnimation;
        SuspendedDelay(350);
       end;
  end;
 end;

 for qq:=1 to 2 do
 begin
  if qq=1 then q:=curplayer else q:=enemy;
  for w:=1 to 6 do
  begin
   {Soul Trap}
   if (q<>pl)and(players[q].creatures[w].cardnum=55) then
   begin
    DuelDelay(200);
    CreatureAct(q,w);
    ChangePower(q,1,false{$ifndef aitesting},cardinfo[55].name+' ^increases owner''s spell power by %1%%1'{$endif});
    SuspendedDelay(200);
   end;

  {Inquisitor}
   if (ActingSpell>0)and(q=curplayer) then
   begin
    if players[q].creatures[w].cardnum=24 then
    begin
     DuelDelay(200);
     CreatureAct(q,w);
     ChangePower(q,1,false{$ifndef aitesting},cardinfo[24].name+' ^increases owner''s spell power by %1%%1'{$endif});
     SuspendedDelay(200);
    end;
   end;

  {Holy Avenger}
   if (q=pl)and(players[q].creatures[w].cardnum=91)and(players[q].creatures[w].life>0)and(actingspell<>130)and((actingspell<>145)or(q=curplayer)) then
   begin
    DuelDelay(300);
    MarkCreature(q,w);
    BurstAttack(q,w,cardinfo[91].logicparam,true);
    waitAnimation;
    SuspendedDelay(150);
   end;

  {Warlock}
   if (players[q].creatures[w].cardnum=147)and(players[q].creatures[w].life>0)and(actingspell<>130)and((actingspell<>145)or(q=curplayer)) then
   begin
    DuelDelay(150);
    MarkCreature(q,w);
    BurstAttack(q,w,1,true);
    waitAnimation;
    SuspendedDelay(150);
   end;
  end;
 end;
end;

procedure tduel.CheckOnDie;
var qq,q,w,e,pl,num:integer;
begin
 if winner=0 then
 for qq:=1 to 2 do
 begin
  if qq=2 then pl:=curplayer else pl:=enemy;
  if (players[pl].life<=0)
  {$ifndef server}or((gamelogic[threadnum].Aiinfo.combating)and(players[3-pl].life>200)and(abs(cureff)<4000000)){$endif}
  then
  begin
   if gamelogic[threadnum].AiInfo.thinking then
   begin
    if pl=gamelogic[threadnum].aiinfo.AiPlayer then q:=-gamelogic[threadnum].AiInfo.Lossvalue else q:=gamelogic[threadnum].Aiinfo.Lossvalue;
    if abs(cureff)>10000000 then
     q:=q div 100;
    q:=int64(q)*(100-numaction) div 100;
    if (pl<>curplayer)and(curplayer=gamelogic[threadnum].AiInfo.AiPlayer)and(numaction=1) then
     inc(cureff,100000);
    players[pl].life:=1000;
    if (q<-40000000)and(gamelogic[threadnum].playersinfo[pl].control>=4) then
     q:=(q div 100)*(100-drawfactor);
    inc(CurEff,q);
   end else
   begin
    if emulation=false then
     showmes(playername(3-pl)+'^ ^wins!');
    winner:=3-pl;
    if (emulation=false)and(numaction>0) then
     inc(players[curplayer].thinktime,(MyTickCount div 1000) - turnstartingtime);
    if gamelogic[threadnum].AiInfo.combating=false then GameOver;
    exit;
   end;
  end;
  for num:=1 to 6 do if players[pl].creatures[num].cardnum<>0 then
  begin
   if players[pl].creatures[num].life=0 then
   begin
    CreatureDies(pl,num);
   end;
  end;
 end;
end;

// damagetype 0 - attack, 1 spells, 2 abilities, -1 loose life
function tDuel.DealDamage(side1,num1,side2,num2,damage,damagetype:integer;needmes:boolean;needdelay:boolean=false):integer;
var q,w,e,r,pl,basicdamage:integer;
    redirected:boolean;
    {$ifndef aitesting}
    s1:string;
    {$endif}
begin
 result:=0;
 redirected:=false;
// LogMessage('Assigning damage ');
// if num1<>0 then logmessage(cardinfo[duel.players[side1].creatures[num1].cardnum].name+' to '+inttostr(side2)+':'+inttostr(num2));
 basicdamage:=damage;
 for w:=1 to 2 do
 begin
  if w=1 then
   pl:=side1
  else
   pl:=3-side1;
  for q:=1 to 6 do
  begin
   case players[pl].creatures[q].cardnum of
    {Vindictive Angel}
    28:if (side2<>pl)and(num2>0) then
       begin
        inc(damage,basicdamage);
        inc(basicdamage,basicdamage);
        markcreature(pl,q);
       end;
    {Druid}
    96:if (damagetype=1)and(side2<>pl)and(side2<>side1)and(num2>0) then
       begin
        inc(damage,basicdamage);
        inc(basicdamage,basicdamage);
        markcreature(pl,q);
       end;
    {Elven Mage}
    123:if (side1=pl)and(damagetype=1) then
        begin
         inc(damage,cardinfo[123].logicparam);
         markcreature(pl,q);
        end;
   end;
  end;
 end;
 if num2=0 then
 begin
  if damage<0 then damage:=0;

  {Guardian Angel}
//  if damagetype<>-1 then
  for q:=1 to 6 do
  if players[side2].creatures[q].cardnum=74 then
  begin
   markcreature(side2,q);
   DealDamage(side1,num1,side2,q,damage,-1,false);
   redirected:=true;
   break;
  end;

  if redirected=false then
  begin
   dec(players[side2].life,damage);
   {$ifndef aitesting}
   inc(players[side1].dealdamage,damage);
   players[side1].lastDamageAmount:=damage;
   if num1=0 then
    players[side1].lastDamageSource:=ActingSpell
   else
    players[side1].lastDamageSource:=players[side1].creatures[num1].cardnum;

   signinfo.addsign(side2,num2,-damage);

   if (needTutorials and 64=64)and(side2=2)and(emulation=false) then
   begin
    needTutorials:=needTutorials xor 64;
    tutorialPause:=true;
    DelayedSignal('UI\COMBAT\SHOWTUTORIAL1',400);
    repeat
     sleep(5);
    until tutorialPause=false;
   end;
   {$endif}
  end;
 end else
 begin
  if players[side2].creatures[num2].life=0 then
   exit;

  {Bargul}
  if (damagetype>0)and(players[side2].creatures[num2].cardnum=119) then
  begin
   damage:=0;
   markcreature(side2,num2);
  end;

  {Treefolk}
  if (damagetype>=0)and(curplayer=side2)and(players[side2].creatures[num2].cardnum=124) then
  begin
   damage:=0;
   markcreature(side2,num2);
  end;

  {Nightmare Horror}
  if (damage>1)and(players[side2].creatures[num2].cardnum=162) then
  begin
   damage:=1;
   markcreature(side2,num2);
  end;

  {Unicorn}
  if (players[side2].creatures[num2].cardnum=42)and(damagetype=1) then
  begin
   markcreature(side2,num2);
   HealCreature(side1,num1,side2,num2,damage,false,false);
   damage:=0;
  end else
  begin
   {$ifndef aitesting}
   signinfo.addsign(side2,num2,-damage,1*byte(damageType=0));
   inc(players[side1].dealdamage,damage);
   {$endif}
   q:=players[side2].creatures[num2].life-damage;
   if q>0 then
    players[side2].creatures[num2].life:=q
   else
    players[side2].creatures[num2].life:=0;
  end;

  {Orc Bersercer}
  if (players[side2].creatures[num2].life>0)and(players[side2].creatures[num2].cardnum=6)and(curplayer=side2) then
  begin
   BurstAttack(side2,num2,damage,true);
   markcreature(side2,num2);
  end;

 end;
 result:=damage;
 if num1>0 then
 begin
  ActingCreature:=side1*10+num1;
 end;

 {$ifndef aitesting}
 if emulation=false then
 if damagetype=0 then
 begin
  if emulation=false then
   ShowMes(cardinfo[players[side1].creatures[num1].cardnum].name+' ^attacks');
 end else
 if (needmes)and(emulation=false) then
 begin
  if damagetype>=0 then
  begin
   if num1=0 then s1:=cardinfo[actingspell].Name else s1:=cardinfo[players[side1].creatures[num1].cardnum].name;
   if num2=0 then
    ShowMes(s1+' ^deals %1 damage to %2`player%%'+inttostr(damage)+'%%'+playername(side2)+'`pl')
   else
    ShowMes(s1+' ^deals %1 damage to %2%%'+inttostr(damage)+'%%'+cardinfo[players[side2].creatures[num2].cardnum].name);
  end else
  begin
   if num2=0 then s1:=playername(side2) else s1:=cardinfo[players[side2].creatures[num2].cardnum].name;
   ShowMes(s1+' ^loses %1 life%%'+inttostr(damage));
  end;
 end;
 {$endif}

 {Crusader}
 if (num1>0)and(players[side1].creatures[num1].cardnum=17)and(num2=0)and(players[side2].life>0)and(redirected=false) then
 begin
  DuelDelay(100);
  creatureact(side1,num1);
  ChangePower(side1,1,false{$ifndef aitesting},cardinfo[17].name+' ^increases owner''s spell power by %1%%1'{$endif});
  SuspendedDelay(400);
 end;

 {Dark Phantom}
 if (num1>0)and(players[side1].creatures[num1].cardnum=128)and(num2=0)and(players[side2].numhandcards>0)and(players[side2].life>0)and(redirected=false) then
 begin
  DuelDelay(100);
  creatureact(side1,num1);
  LoseCard(side2,1);
  SuspendedDelay(200);
 end;

 {Vampire Lord}
 if (damagetype>=0)and(damage>0)and(num1>0) then
 for q:=1 to 6 do
 if players[side1].creatures[q].cardnum=59 then
 begin
  if needdelay then
   delayedeffects[side1,q]:=side1*10+num1
  else
  begin
   DuelDelay(300);
   burstattack(side1,num1,2,true);
   markcreature(side1,q);
   SuspendedDelay(200);
  end;
 end;

 {Undead Librarian}
 if (curplayer=side2)and(num2>0)and(players[side2].creatures[num2].cardnum=115) then
 begin
  if needdelay then
   delayedeffects[side2,num2]:=1
  else
  begin
   DuelDelay(200);
   creatureact(side2,num2);
   GetCard(side2,true,115,side2*10+num2);
   SuspendedDelay(200);
  end;
 end;
end;

procedure tDuel.GetSpecificCard(pl,card:integer;source:integer=0;sourceparam:integer=0;shownewcard:boolean=true);
begin
 if players[pl].numdeckcards<>50 then
  inc(players[pl].numdeckcards);
 gamelogic[threadnum].playersinfo[pl].curdeck.cards[players[pl].numdeckcards]:=card;
 GetCard(pl,true,source,sourceparam,shownewcard);
end;

procedure tduel.GetCard(pl:integer;showmessage:boolean=false;source:integer=0;sourceparam:integer=0;shownewcard:boolean=false;showeffect:boolean=true;isreplace:boolean=false);
var q,w,e,r,n:integer;
    ds:cardinal;
    a:tAiAction;
begin
 DuelDelay(1);
 if players[pl].numdeckcards=0 then
 begin
  if (gamelogic[threadnum].AiInfo.thinking=false) then
  begin
//   players[pl].deck:=playersinfo[pl].Deck;
   gamelogic[threadnum].playersinfo[pl].curdeck.cards:=gamelogic[threadnum].playersinfo[pl].Deck.cards;
//   forcelogmessage('Deck shuffling');
   ds:=deckseed;
   deckseed:=players[pl].localcounter;
   gamelogic[threadnum].playersinfo[pl].curdeck.Shuffle;
   players[pl].localcounter:=deckseed;
   deckseed:=ds;
   players[pl].numdeckcards:=gamelogic[threadnum].playersinfo[pl].curdeck.DeckSize;
   if players[pl].numdeckcards=0 then
    players[pl].numdeckcards:=40;
  end else inc(players[pl].numdeckcards);
 end;

 if (Emulation)and(players[pl].numhandcards=7)and(pl=gamelogic[threadnum].aiinfo.AiPlayer)and(isreplace=false) then
  Dec(CurEff,15000);

 if (gamelogic[threadnum].aiinfo.thinking)and(curplayer=gamelogic[threadnum].aiinfo.AiPlayer) then
 begin
  inc(DrawFactor);
  for q:=1 to 6 do
  if (players[pl].creatures[q].cardnum=158)and(players[pl].creatures[q].abilitywas) then
   inc(cureff,1000);
 end;

 if emulation=false then
  lockdrawing;

 if players[pl].numhandcards=7 then
 begin
  for q:=1 to 7 do
  begin
   players[pl].handcards[q]:=players[pl].handcards[q+1];
  end;
 end else
 begin
  inc(players[pl].numhandcards);
 end;
 n:=players[pl].numhandcards;
 if (gamelogic[threadnum].AiInfo.thinking=false)or(shownewcard) then
 begin
{  if (players[pl].numdeckcards>50)or(players[pl].numdeckcards<=0)or(n<=0)or(n>8)or(pl>2)or(threadnum>=numAIthreads) then
   forcelogmessage('123')
  else}
  q:=gamelogic[threadnum].playersinfo[pl].curdeck.cards[players[pl].numdeckcards];
  {$IFNDEF AITESTING}
  if (q=-5)and(gamelogic[threadnum].playersinfo[pl].control>0)and(players[pl].numdeckcards>1) then
  begin
   players[pl].handcards[n]:=0;
   FindBestAction(a,threadnum,pl);
   if a.ActionResult<-30000 then
   begin
    dec(players[pl].numdeckcards);
    q:=gamelogic[threadnum].playersinfo[pl].curdeck.cards[players[pl].numdeckcards];
   end;
  end;
  {$ENDIF}
  players[pl].handcards[n]:=q;
  dec(players[pl].numdeckcards);
 end else
  players[pl].handcards[n]:=0;
 if emulation=false then
  leavedrawing;

 {$ifndef aitesting}
 if (Emulation=false)and(showeffect) then
   EFF_AddHandCard(pl,players[pl].handcards[n],sourceparam);

 showmovecard:=false;
 if (showmessage)and(emulation=false) then
 if shownewcard then
 begin
  if source=0 then
   ShowMes(playername(pl)+'^ ^receives %1 card%%'+cardinfo[players[pl].handcards[n]].name)
  else
   ShowMes(playername(pl)+'^ ^receives %1 card (effect of %2)%%'+cardinfo[players[pl].handcards[n]].name+'%%'+cardinfo[source].name)
 end else
 if isreplace=false then
 begin
  if source=0 then
   ShowMes(playername(pl)+'^ ^receives a card')
  else
   ShowMes(playername(pl)+'^ ^receives a card (effect of %1)%%'+cardinfo[source].name)
 end else
  ShowMes(playername(pl)+'^ ^replaces a card')
 else
 if (showeffect)and(emulation=false) then
  Showmes('');
 showmovecard:=true;

 {$endif}

 if (gamelogic[threadnum].AiInfo.thinking)and(pl=curplayer) then
  inc(CurEff,10-numaction);

 {Seeker for Knowledge}
 for q:=1 to 6 do
 if players[pl].creatures[q].cardnum=94 then
 begin
  MarkCreature(pl,q);
  burstattack(pl,q,1,true);
 end;
 {$ifndef aitesting}
// CheckonDIe; Опасное место
 {$endif}
end;

function tduel.MassDamage(pl,num,damage,damagetype,targettype:integer):integer;
// TargetType  0-all enemy creatures, 1-all enemies, 2-all creatures;
var q,w:integer;
begin
 result:=0;
 w:=0;
 if targettype=1 then result:=DealDamage(pl,num,3-pl,0,damage,damagetype,false,true);
 for q:=1 to 6 do if players[3-pl].creatures[q].cardnum<>0 then
 begin
  w:=DealDamage(pl,num,3-pl,q,damage,damagetype,false,true);
  if w>result then result:=w;
 end;
 if targettype=2 then
 for q:=1 to 6 do if players[pl].creatures[q].cardnum<>0 then
 begin
  w:=DealDamage(pl,num,pl,q,damage,damagetype,false,true);
  if w>result then result:=w;
 end;
end;

procedure tDuel.LoseCard(pl,num:integer;showmessage:boolean=true);
var q,w,e,r,n:integer;
begin
 DuelDelay(1);
 if num=0 then num:=1;
 if num>players[pl].numhandcards then exit;
 n:=players[pl].handcards[1];
 dec(players[pl].numhandcards);
 for q:=num to players[pl].numhandcards do
 begin
  players[pl].handcards[q]:=players[pl].handcards[q+1];
 end;
 if Emulation=false then
  EFF_LoseHandCard(pl,num);

 if (showmessage)and(emulation=false) then
 begin
  if pl=1 then
   ShowMes(playername(pl)+'^ ^loses a card^ ( %1 )%%'+cardinfo[n].name)
  else
   ShowMes(playername(pl)+'^ ^loses a card');
 end;
end;

procedure tduel.CreatureReturns(side,num,pl:integer);
var q,w,e,r,t,n:integer;
begin
 DuelDelay(1);
 e:=players[side].creatures[num].cardnum;
 players[side].creatures[num].cardnum:=0;
 players[side].creatures[num].life:=0;
 if players[pl].numhandcards=7 then
 begin
  for q:=1 to 7 do
   players[pl].handcards[q]:=players[pl].handcards[q+1];
 end else
 begin
  inc(players[pl].numhandcards);
 end;
 n:=players[pl].numhandcards;
 players[pl].handcards[n]:=e;
 if emulation=false then
 begin
  EFF_ReturnCreatureToHand(side,num,pl);
  ShowMes(cardinfo[e].name+' ^returns to %1''s hand%%'+playername(pl));
 end;
end;

function tDuel.CanAttack(pl,num:integer):boolean;
var q:integer;
begin
 if players[pl].creatures[num].new then
 begin
  //Minotaur Commander}
  for q:=1 to 6 do
  if players[pl].creatures[q].cardnum=129 then
  begin
   result:=true;
   exit;
  end;
  result:=false;
 end else
  result:=true;
end;

function tduel.AttackAttempt(pl,num:integer;needdelay:boolean=false):boolean;
begin
 if (CanAttack(pl,num)=false)or(getAttack(pl,num)=0) then
  result:=false
 else
 begin
  result:=true;
  if emulation=false then
  begin
   waitAnimation;
   if needdelay then
    Sleep(400)
   else
    sleep(100);
  end;
  CreatureAttacks(pl,num,3-pl);

  {Ancient Zubr, additional attack}
  if players[pl].creatures[num].cardnum=41 then
   CreatureAttacks(pl,num,3-pl);
 end;
end;

procedure tduel.CreatureAttacks(pl,num,opp:integer);
var q,w,e,cn:integer;
begin
 DuelDelay(1);
 cn:=players[pl].creatures[num].cardnum;

 {$ifndef aitesting}
 {$ifndef server}
 if emulation=false then
 begin
  waitAnimation;
//  Signal('Sound\play\CreatureAttacks');
 end;
 if (pl=curplayer)and(Emulation=false) then
 begin
  if pl=1 then
  begin
   if (needTutorials and 1=1)and(players[opp].creatures[num].cardnum<>0) then
   begin
    needTutorials:=needTutorials xor 1;
    tutorialPause:=true;
    Signal('UI\COMBAT\SHOWTUTORIAL8',num);
    repeat
     sleep(5);
    until tutorialPause=false;
   end;
   if (needTutorials and 2=2)and(players[opp].creatures[num].cardnum=0) then
   begin
    needTutorials:=needTutorials xor 2;
    tutorialPause:=true;
    Signal('UI\COMBAT\SHOWTUTORIAL9',num);
    repeat
     sleep(5);
    until tutorialPause=false;
   end;
  end;
  EFF_CreatureAttack(pl,num);
 end else CreatureAct(pl,num);
 {$endif}
 {$endif}
 if (players[opp].creatures[num].cardnum=0)or(pl<>curplayer) then
 begin
  DealDamage(pl,num,opp,0,getattack(pl,num),0,false);
 end else
  DealDamage(pl,num,opp,num,getattack(pl,num),0,false);
 CheckOnDie;
end;

procedure tDuel.CreatureComes(pl,num:integer;oldslot:integer=0);
var q,w,e,r,card:integer;
begin
 card:=players[pl].creatures[num].cardnum;

 inc(players[pl].summoncreatures);

 {$ifdef server}
 if cardinfo[card].isElf then
  inc(players[pl].ElvesSummoned);
 if card=15 then
  inc(players[pl].dragonssummoned);
 {$endif}

 case card of
  {Orc Mystic}
  7:begin
     repeat
      w:=players[pl].localrandom(cardinfo[7].logicparam);
     until (cardinfo[w].element=2)and(cardinfo[w].life=0);
     if gamelogic[threadnum].AiInfo.thinking=false then
      GetSpecificCard(pl,w,0,pl*10+num,pl=1)
     else
      GetCard(pl);
    end;
  {Goblin Saboteur}
  13:if players[3-pl].spellpower>0 then
     begin
      creatureact(pl,num);
      Changepower(3-pl,-1,false{$ifndef aitesting},cardinfo[card].name+' ^decreases opponent''s spell power by %1%%1'{$endif});
     end;
  {Apprentice}
  20:begin
      creatureact(pl,num);
      ChangePower(pl,1,false{$ifndef aitesting},cardinfo[card].name+' ^increases owner''s spell power by %1%%1'{$endif});
     end;
  {Bishop}
  27:begin
      creatureact(pl,num);
      AddMana(pl,cardinfo[27].logicparam{$ifndef aitesting},cardinfo[27].name+' ^generates %1 mana for its owner%%'+inttostr(cardinfo[27].logicparam){$endif});
     end;
  {Halfling}
  35:begin
//      MarkCreature(pl,num);
      GetCard(pl,true,35,pl*10+num);
     end;
  {Lich}
  53:begin
      creatureact(pl,num);
      q:=MassDamage(pl,num,cardinfo[53].logicparam,2,1);
      if (q>0)and(emulation=false) then
       ShowMes(cardinfo[53].name+' ^deals %1 damage%%'+inttostr(cardinfo[53].logicparam));
      CheckDelayedEffects;
     end;
  {Harpy}
  81:if (players[pl].spellpower=4)and(gamelogic[threadnum].AiInfo.thinking) then
      dec(cureff,20000);
  {Gryphon}
  113:begin
       CreatureAttacks(pl,num,3-pl);
      end;
  {Goblin Thief}
  118:if players[3-pl].numhandcards>0 then
      begin
       creatureact(pl,num);
       LoseCard(3-pl,1);
      end;
  {Bargul}
  119:if players[1].hascreatures+players[2].hascreatures>1 then
      begin
       creatureact(pl,num);
       q:=MassDamage(pl,num,cardinfo[119].logicparam,2,2);
       if (q>0)and(emulation=false) then
        ShowMes(cardinfo[119].name+' ^damages another creatures');
       CheckDelayedEffects;
      end;
  {TreeFolk}
  124:begin
       e:=0;
       q:=pl;
//       for q:=1 to 2 do
       for w:=1 to 6 do
       if players[q].creatures[w].cardnum=124 then
        inc(e);
       if e>1 then
       begin
        creatureact(pl,num);
        for q:=1 to e-1 do
         GetCard(pl,true,124,pl*10+num);
       end;
      end;
  {Sword Master}
  134:begin
       CreatureAttacks(pl,num,3-pl);
       if players[3-pl].life>0 then
        CreatureAttacks(pl,num,3-pl);
      end;
  {Timeweaver}
  135:begin
       if (num>1)and(players[pl].creatures[num-1].cardnum<>0) then
        CreatureAttacks(pl,num-1,3-pl);
       if (num<6)and(players[pl].creatures[num+1].cardnum<>0) then
        CreatureAttacks(pl,num+1,3-pl);
      end;
  {Familiar}
  140:begin
       creatureact(pl,num);
       AddMana(pl,1{$ifndef aitesting},cardinfo[140].name+' ^generates %1 mana for its owner%%1'{$endif});
      end;
  {Angry Bird}
  149:if players[3-pl].creatures[num].life>0 then
      begin
       CreatureAct(pl,num);
       DealDamage(pl,num,3-pl,num,cardinfo[149].logicparam,2,true);
      end else
      if emulation then
       dec(CurEff,10000);
 end;
 CheckonDie;
 if winner>0 then exit;

 {Wisp}
 if oldslot=112 then
 for q:=1 to cardinfo[112].logicparam do
  GetCard(pl,true,112,pl*10+num);

 SuspendedDelay(250);

 if winner=0 then
 for q:=1 to 6 do
 begin
  case players[pl].creatures[q].cardnum of
   {Forest Sprite}
{   16:if abs(q-num)=1 then
      begin
       DuelDelay(100);
       CreatureAct(pl,q);
       GetCard(pl,true,16,pl*10+q);
       SuspendedDelay(300);
      end;}
   {Elven Lord}
   37:begin
       if (cardinfo[card].isElf)and(q<>num) then
       begin
        DuelDelay(100);
        CreatureAct(pl,q);
        GetCard(pl,true,37,pl*10+q);
        SuspendedDelay(300);
       end;
      end;
   {Vampire Elder}
   57:begin
       if (cardinfo[card].isvampire)and(q<>num) then
       begin
        DuelDelay(100);
        CreatureAct(pl,q);
        GetCard(pl,true,57,pl*10+q);
        SuspendedDelay(300);
       end;
      end;
   {Lord of the Coast}
   93:begin
       if (q<>num) then
       begin
        DuelDelay(50);
        CreatureAct(pl,q);
        BurstAttack(pl,num,cardinfo[93].logicparam,true);
        if emulation=false then
         Showmes(cardinfo[93].name+' ^increases attack of %1 by %2%%'+cardinfo[card].name+'%%'+inttostr(cardinfo[93].logicparam));
        SuspendedDelay(250);
       end;
      end;
   {Heretic}
   120:if cardinfo[card].element=2 then
       begin
        DuelDelay(150);
        creatureact(pl,q);
        ChangePower(pl,1,false{$ifndef aitesting},cardinfo[120].name+' ^increases owner''s spell power by %1%%1'{$endif});
        SuspendedDelay(300);
       end;
   {Siege Golem}
   142:if abs(q-num)=1 then
       begin
        DuelDelay(100);
        r:=MassDamage(pl,q,cardinfo[142].logicparam,2,0);
        if (r>0)and(emulation=false) then
        begin
         CreatureAct(pl,q);
         ShowMes(cardinfo[142].name+' ^deals %1 damage to opponent''s creatures%%'+inttostr(cardinfo[142].logicparam));
         SuspendedDelay(300);
        end;
        CheckDelayedEffects;
       end;
   {Elven Hero}
{   144:if (q<>num)and(abs(q-num)=1) then
       begin
        DuelDelay(100);
        CreatureAttacks(pl,q,3-pl);
        SuspendedDelay(300);
       end;}
   {Astral chaneller}
   155:if abs(q-num)=1 then
       begin
        DuelDelay(100);
        CreatureAct(pl,q);
        ChangePower(pl,1,false{$ifndef aitesting},cardinfo[155].name+' ^increases owner''s spell power by %1%%1'{$endif});
        SuspendedDelay(250);
       end;
  end;
 end;
 CheckOnDie;
 {$ifndef server}
 {$ifndef aitesting}
 if (needtutorials and 8=8)and(pl=1)and(emulation=false) then
 begin
  tutorialPause:=true;
  needtutorials:=needtutorials xor 8;
  DelayedSignal('UI\COMBAT\SHOWTUTORIAL5',500);
  repeat
   sleep(5);
  until tutorialPause=false;
 end;
 {$endif}
 {$endif}
end;

procedure tDuel.SpellCasted(pl,card,target:integer);
var q,qq,w,e,r,t,n,c,side2,num2:integer;
    countered:boolean;
begin
 inc(players[pl].castspells);
 ActingSpell:=card;
 ActingCreature:=0;
 if target>=0 then
 begin
  side2:=curplayer;
  num2:=target;
 end else
 begin
  side2:=3-curplayer;
  num2:=-target;
 end;
 case card of
  -1:begin
      AddMana(curplayer,1{$ifndef aitesting},'default'{$endif});
      if (emulation)and(gamelogic[threadnum].PlayersInfo[curplayer].control=1) then
       dec(cureff,3000);
//      inc(players[curplayer].mana);
//      addlife(curplayer,2);
     end;
  {Unknown card, for AI purposes only}
  0:begin
     w:=players[curplayer].mana;
     if w>3 then
      w:=3;
     inc(cureff,1250*w);
     dec(players[curplayer].mana,w);
    end;
  {Lightning Bolt}
  3:begin
     DealDamage(pl,0,side2,num2,cardinfo[3].logicparam,1,true);
    end;
  {Fire Ball}
  4:begin
     for q:=1 to 6 do if q<>num2 then
      DealDamage(pl,0,side2,q,cardinfo[4].logicparam2,1,false,true);
     DealDamage(pl,0,side2,num2,cardinfo[4].logicparam,1,true,true);
     CheckDelayedEffects;
    end;
  {Planar Burst}
  10:begin
      r:=MassDamage(pl,0,cardinfo[10].logicparam,1,2);
      if emulation=false then
       ShowMes(cardinfo[10].name+' ^deals %1 damage%%'+inttostr(r));
      CheckDelayedEffects;
     end;
  {Flame Wave}
  12:begin
      r:=MassDamage(pl,0,cardinfo[12].logicparam,1,0);
      if emulation=false then
       ShowMes(cardinfo[12].name+' ^deals %1 damage%%'+inttostr(r));
      CheckDelayedEffects;
     end;
  {Chain Lightning}
  14:begin
      r:=MassDamage(pl,0,players[pl].spellpower,1,1);
      if emulation=false then
       ShowMes(cardinfo[14].name+' ^deals %1 damage%%'+inttostr(r));
      CheckDelayedEffects;
     end;
  {Clone}
  18:begin
      c:=players[side2].creatures[num2].cardnum;
      GetSpecificCard(pl,c,0,side2*10+num2);
      if (gamelogic[threadnum].AiInfo.thinking)and(pl=curplayer) then
      begin
       dec(CurEff,300);
       if gamelogic[threadnum].playersinfo[pl].control>=5 then
        dec(cureff,500);
      end;
     end;
  {Justice}
  21:begin
      r:=0;
      for q:=1 to 6 do
      if players[3-pl].creatures[q].cardnum<>0 then
       inc(r,DealDamage(pl,0,3-pl,q,GetAttack(3-pl,q),1,false,true));
      if (r>0)and(emulation=false) then
       ShowMes(cardinfo[21].name+' ^deals damage to opponent''s creatures');
      CheckDelayedEffects;
      if players[3-pl].numhandcards>0 then
       LoseCard(3-pl,1);
     end;
  {Returning Wind}
  22:begin
      CreatureReturns(side2,num2,side2);
      if side2=pl then
       AddMana(pl,cardinfo[22].logicparam{$ifndef aitesting},'default'{$endif});
     end;
  {Wind of Command}
  25:begin
      if (Emulation) then
      begin
       if side2=pl then
        dec(cureff,3000);
       q:=cardinfo[players[side2].creatures[num2].cardnum].cost;
       if q<4 then
        Dec(CurEff,1000*(4-q));
      end;
      CreatureReturns(side2,num2,pl);
     end;
  {Inspiration}
  26:begin
      r:=0;
      e:=0;
      for q:=1 to 6 do
      if players[pl].creatures[q].cardnum<>0 then
      begin
       inc(r);
       if CanAttack(pl,q) then
        inc(e);
       BurstAttack(pl,q,cardinfo[26].logicparam);
      end;
      if (r>0)and(emulation=false) then
       ShowMes(cardinfo[26].name+' ^increases attack of caster''s creatures');
      if (e=0)and(emulation) then
       dec(cureff,10000);
     end;
  {Preachment}
  29:begin
      players[pl].creatures[num2]:=players[side2].creatures[num2];
      players[side2].creatures[num2].life:=0;
      players[side2].creatures[num2].cardnum:=0;
      if emulation=false then
      begin
       EFF_MoveCreatureToSlot(side2,num2,pl,num2,1);
       Showmes(cardinfo[players[pl].creatures[num2].cardnum].name+' ^change its owner');
      end;
      players[pl].creatures[num2].new:=true;
      if players[pl].creatures[num2].cardnum=16 {Forest Sprite} then
       players[pl].creatures[num2].abilitywas:=true
      else
       players[pl].creatures[num2].abilitywas:=false;
     end;
  {Divine Justice}
  30:begin
      HealCreature(pl,0,side2,num2,cardinfo[30].logicparam,true,false);
      r:=0;
      for q:=1 to 2 do
      begin
       if q=1 then
        e:=3-pl
       else
        e:=pl;
       for w:=1 to 6 do if (players[e].creatures[w].cardnum<>0)and((e<>side2)or(w<>num2)) then
        inc(r,dealdamage(pl,0,e,w,cardinfo[30].logicparam,1,false));
      end;
      if r>0 then ShowMes(cardinfo[card].name+' ^deals %1 damage to each other creature^%%'+inttostr(cardinfo[30].logicparam));
      CheckDelayedEffects;
     end;
  {Elven Ritual}
  33:begin
      AddMana(pl,cardinfo[33].logicparam{$ifndef aitesting},'default'{$endif});
      AddLife(pl,cardinfo[33].logicparam2{$ifndef aitesting},'default'{$endif});
     end;
  {Pure Knowledge}
  44:begin
      for q:=1 to cardinfo[44].logicparam do
       GetCard(pl,true);
     end;
  {Rejuvenation}
  45:begin
      AddLife(pl,cardinfo[45].logicparam{$ifndef aitesting},'default'{$endif});
      for q:=1 to cardinfo[45].logicparam2 do
       GetCard(pl,true);
     end;
  {Soul Explosion}
  46:begin
      CreatureDies(side2,num2);
      if players[3-side2].creatures[num2].cardnum<>0 then
       CreatureDies(3-side2,num2);
     end;
  {Steal Essence}
  48:begin
      c:=players[side2].creatures[num2].cardnum;
      DealDamage(pl,0,side2,num2,cardinfo[48].logicparam,1,true);
      GetSpecificCard(pl,c,0,side2*10+num2);
     end;
  {Dark Slaying}
  51:begin
      CreatureDies(side2,num2);
     end;
  {Death Touch}
  58:begin
      CreatureDies(side2,num2);
      AddLife(pl,cardinfo[58].logicparam{$ifndef aitesting},'default'{$endif});
     end;
  {Soul Plague}
  60:begin
      c:=cardinfo[players[side2].creatures[num2].cardnum].cost;
      CreatureDies(side2,num2);
      for qq:=1 to 2 do
      begin
       if qq=1 then q:=enemy else q:=pl;
       for w:=1 to 6 do
       begin
        e:=players[q].creatures[w].cardnum;
        if (e<>0)and(cardinfo[e].cost<c) then
         CreatureDies(q,w);
       end;
      end;
     end;
  {Polymorph}
  63:begin
      q:=players[side2].creatures[num2].cardnum;
      players[side2].creatures[num2].cardnum:=-2;
      players[side2].creatures[num2].life:=2;
      players[side2].creatures[num2].counter:=0;
      players[side2].creatures[num2].bonus:=0;
      players[side2].creatures[num2].abilitywas:=false;
      if emulation=false then
      begin
       EFF_CreatureReplaced(side2,num2);
       ShowMes(cardinfo[q].name+' ^is polymorphed to sheep');
      end;
     end;
  {Blood Ritual}
  67:begin
      q:=players[side2].creatures[num2].life;
      CreatureDies(side2,num2);
      r:=MassDamage(pl,0,q,1,0);
      if emulation=false then
       ShowMes(cardinfo[67].name+' ^deals %1 damage%%'+inttostr(r));
      CheckDelayedEffects;
     end;
  {Demonic Rage}
  68:begin
      BurstAttack(side2,num2,cardinfo[68].logicparam2);
      DealDamage(pl,0,side2,num2,cardinfo[68].logicparam,1,true);
     end;
  {Fire Bolt}
  70:begin
      DealDamage(pl,0,side2,num2,cardinfo[70].logicparam,1,true);
     end;
  {Meditation}
  73:begin
      ChangePower(pl,1,false{$ifndef aitesting},cardinfo[73].name+' ^increases %1''s spell power by %2%%'+playername(pl)+'%%1'{$endif});
      if players[pl].spellpower>=cardinfo[73].logicparam then
      AddLife(pl,cardinfo[73].logicparam2{$ifndef aitesting},'default'{$endif});
     end;
  {Cure}
  75:begin
      AddLife(pl,cardinfo[75].logicparam{$ifndef aitesting},'default'{$endif});
     end;
  {Virtuous Cycle}
  76:begin
      q:=players[pl].hasCreatures;
      if q>0 then
       AddLife(pl,q*cardinfo[76].logicparam{$ifndef aitesting},'default'{$endif});
      GetCard(pl,true);
     end;
  {Nature Ritual}
  77:begin
      if (side2<>pl)and(Emulation) then
       dec(cureff,5);
      HealCreature(pl,0,side2,num2,99,true,false);
      for q:=1 to cardinfo[77].logicparam do
       GetCard(pl,true);
     end;
  {Offering to Dorlak}
  80:begin
      CreatureDies(side2,num2);
      for q:=1 to cardinfo[80].logicparam do
       GetCard(pl,true);
     end;
  {Suppression}
  89:begin
      DealDamage(pl,0,side2,num2,getattack(side2,num2)*3,1,true);
     end;
  {Hasten}
  95:begin
      ActingSpell:=0;
      CreatureAttacks(side2,num2,3-side2);
      GetCard(pl,true);
     end;
  {Ritual of Life}
  97:begin
      for q:=1 to cardinfo[97].logicparam do
       GetCard(pl,true);
      AddMana(pl,cardinfo[97].logicparam2{$ifndef aitesting},'default'{$endif});
     end;
  {Energy Wave}
  102:begin
//       e:=players[curplayer].killcreatures;
       t:=MassDamage(pl,0,cardinfo[102].logicparam,1,0);
       r:=0;
       for q:=1 to 6 do
       if players[pl].creatures[q].cardnum<>0 then
        r:=r+HealCreature(pl,0,pl,q,cardinfo[102].logicparam2,false,false);
       if emulation=false then
       begin
        if t>0 then
         ShowMes(cardinfo[card].name+' ^deals %1 damage%%'+inttostr(t))
        else
        if r>0 then
         Showmes('');
       end;
       CheckDelayedEffects;
       CheckonDie;
//        r:=players[curplayer].killcreatures-e;
//        if r>0 then
//         AddMana(pl,r{$ifndef aitesting},'default'{$endif});
      end;
  {Acidic Bolt}
  105:begin
       q:=players[side2].creatures[num2].life;
       DealDamage(pl,0,side2,num2,(q+1) div 2,1,true);
       GetCard(pl);
      end;
  {Chaotic Wave}
  106:begin
       r:=MassDamage(pl,0,cardinfo[106].logicparam,1,0);
       if (r>0)and(emulation=false) then
        ShowMes(cardinfo[106].name+' ^deals %1 damage%%'+inttostr(r));
       CheckDelayedEffects;
       ChangePower(3-pl,-1,false{$ifndef aitesting},cardinfo[106].name+' ^decreases opponent''s spell power by %1%%1'{$endif});
     end;
  {Ascension}
  108:begin
       ChangePower(pl,1,false{$ifndef aitesting},cardinfo[108].name+' ^increases caster''s spell power by %1%%1'{$endif});
{       w:=0;
       for q:=1 to 6 do
       if players[pl].creatures[q].cardnum<>0 then
       begin
        inc(w);
        inc(players[pl].creatures[q].counter);
       end;
       if w>0 then
       ShowMes(cardinfo[108].name+' increases attack of caster''s creatures');}
      end;
  {Anathema}
  109:begin
       r:=0;
       for q:=1 to 2 do
       for w:=1 to 6 do
       if players[q].creatures[w].cardnum<>0 then
        inc(r,getattack(q,w));
       DealDamage(pl,0,side2,num2,r,1,true);
      end;
  {Ritual of Devourment}
  114:begin
       q:=players[side2].creatures[num2].life;
       CreatureDies(side2,num2);
       AddLife(side2,q{$ifndef aitesting},'default'{$endif});
      end;
  {United Prayer}
  122:begin
       w:=0;
       for q:=1 to 6 do
       if players[pl].creatures[q].cardnum<>0 then
        inc(w);
       if w>0 then
        ChangePower(pl,w,false{$ifndef aitesting},cardinfo[122].name+' ^increases %1''s spell power by %2%%'+playername(pl)+'%%'+inttostr(w){$endif})
       else
       if emulation then
        dec(CurEff,10000);
      end;
  {Nature's Touch}
  125:begin
       HealCreature(pl,0,side2,num2,cardinfo[125].logicparam,true,false);
       if players[3-pl].creatures[num2].cardnum<>0 then
       DealDamage(pl,0,3-pl,num2,cardinfo[125].logicparam2,1,true);
      end;
  {Drain Life}
  126:begin
       DealDamage(pl,0,side2,num2,cardinfo[126].logicparam,1,true);
       AddLife(pl,cardinfo[126].logicparam2{$ifndef aitesting},'default'{$endif});
      end;
  {Void Bolt}
  127:begin
       w:=0;
       for q:=1 to 6 do
       if players[pl].creatures[q].cardnum=0 then
        inc(w);
       DealDamage(pl,0,side2,num2,w*cardinfo[127].logicparam,1,true);
      end;
  {Armageddon}
  130:begin
      for q:=1 to 6 do
      if players[3-pl].creatures[q].cardnum<>0 then
       CreatureDies(3-pl,q);
      for q:=1 to 6 do
      if players[pl].creatures[q].cardnum<>0 then
       CreatureDies(pl,q);
      ChangePower(pl,-2,false{$ifndef aitesting},''{$endif});
      ChangePower(3-pl,-2,false{$ifndef aitesting},''{$endif});
      if emulation=false then
       ShowMes(cardinfo[130].name+' ^decreases each player''s spell power by %1%%2');
     end;
  {Refilled Memory}
  136:begin
       if (emulation)and(players[pl].mana<20) then
        Dec(cureff,2000);
       players[pl].numhandcards:=0;
       if emulation=false then
        EFF_LoseAllCards(pl);
       for q:=1 to cardinfo[136].logicparam do
        GetCard(pl,true);
      end;
  {Final Sacrifice}
  138:begin
       q:=players[pl].life div 2;
       DealDamage(pl,0,pl,0,q,1,false);
       DealDamage(pl,0,3-pl,0,q,1,false);
       if emulation=false then
        ShowMes(cardinfo[138].name+' ^deals %1 damage to each player%%'+inttostr(q));
      end;
  {Fire Storm}
  139:begin
       r:=MassDamage(pl,0,cardinfo[139].logicparam,1,2);
       if emulation=false then
        ShowMes(cardinfo[139].name+' ^deals %1 damage%%'+inttostr(r));
       CheckDelayedEffects;
       GetCard(pl,true);
      end;
  {Triumph of Good}
  145:begin
       for q:=1 to 6 do
       if players[3-pl].creatures[q].cardnum<>0 then
        CreatureDies(3-pl,q);
      end;
  {Test of Endurance}
  156:begin
      r:=MassDamage(pl,0,cardinfo[156].logicparam,1,2);
      if emulation=false then
       ShowMes(cardinfo[156].name+' ^deals %1 damage%%'+inttostr(r));
      CheckDelayedEffects;
      CheckonDie;
      w:=0;
      for q:=1 to 6 do
      if (players[pl].creatures[q].cardnum<>0) then
      begin
       MarkCreature(pl,q);
       inc(w,{getAttack(pl,q)}cardinfo[156].logicparam2);
      end;
      if w>0 then
      begin
       r:=DealDamage(pl,0,3-pl,0,w,1,false,false);
       if emulation=false then
       begin
        DelayedSignal('Sound\Play\SpellDamage',0,0);
        ShowMes(cardinfo[156].name+' ^deals %1 damage to opponent%%'+inttostr(r));
       end;
      end;
     end;
  {Incinerate}
  157:begin
       CreatureDies(side2,num2);
       r:=MassDamage(pl,0,cardinfo[157].logicparam,1,0);
       if (r>0)and(emulation=false) then
        ShowMes(cardinfo[157].name+' ^deals %1 damage%%'+inttostr(r));
       CheckDelayedEffects;
      end;
 end;
 CheckOnDie;
 SuspendedDelay(250);
 if winner=0 then
 for q:=1 to 6 do
 begin
  case players[pl].creatures[q].cardnum of
   {Dragon, Except Preachment to him}
(*  15:if (players[3-pl].spellpower>0)and((card<>29)or(q<>num2)) then
      begin
       DuelDelay(100);
       creatureact(pl,q);
       w:=2;
       if players[3-pl].spellpower<2 then
        w:=players[3-pl].spellpower;
       ChangePower(3-pl,-w,false{$ifndef aitesting},cardinfo[15].name+' ^decreases opponent''s spell power by %1%%'+inttostr(w){$endif});
       SuspendedDelay(450);
      end;*)
   {Elven Mystic, Except Preachment to him}
   65:if (card<>29)or(q<>num2) then
      begin
       DuelDelay(100);
       MarkCreature(pl,q);
       burstattack(pl,q,cardinfo[65].logicparam,true);
       SuspendedDelay(300);
      end;
   {Heretic}
   120:if cardinfo[card].element=2 then
       begin
        DuelDelay(100);
        creatureact(pl,q);
        ChangePower(pl,1,false{$ifndef aitesting},cardinfo[120].name+' ^increases owner''s spell power by %1%%1'{$endif});
        SuspendedDelay(400);
       end;
  end;
 end;
 CheckOnDie;
 if winner>0 then exit;
 ActingSpell:=0;
end;

procedure tDuel.LoseRitualOfPower(pl,num:integer);
var q:integer;
begin
 if gamelogic[threadnum].PlayersInfo[pl].control=-1 then
  LoseCard(pl,num,false)
 else
 begin
  for q:=1 to players[pl].numhandcards do
  if players[pl].handcards[q]=-1 then
  begin
   LoseCard(pl,q,false);
   break;
  end;
 end;
end;

procedure tDuel.UseAbility(num,target:integer);
var q,w,e,r,el,n,c,pl,side2,num2:integer;
    s,s1,s2:string;
    cr:tcreature;
begin
 if emulation=false then
 begin
  ForceLogMessage('UseAbility, hash='+inttostr(getPlayerHash(curplayer)));
  ActivateCard(0);
 end;
 inc(numaction);
 pl:=curplayer;
 if num>0 then
  n:=players[curplayer].creatures[num].cardnum
 else
  n:=-3;

 {$ifndef aitesting}
 if (emulation=false)and(gamelogic[threadnum].playersinfo[curplayer].control<>0)and(curplayer<>1) then
 begin
  if num>0 then
   ShowCardInfo(n+1000,num,target)
  else
  begin
   players[curplayer].numhandcards:=1;
   players[curplayer].handcards[1]:=-3;
   EFF_AddManaStorm;
   ShowCardInfo(-3,1,0);
   players[curplayer].numhandcards:=0;
   EFF_RemoveManaStorm;
  end;
 end;
 if (emulation=false)and(n=-3)and(gamelogic[threadnum].playersinfo[curplayer].control=0) then
   EFF_ManaStorm;
 {$endif}

 if (n<>-3)and(n<>62)and(n<>66) then
  players[curplayer].creatures[num].abilitywas:=true;
 if target>=0 then
 begin
  side2:=curplayer;
  num2:=target;
 end else
 begin
  side2:=3-curplayer;
  num2:=-target;
 end;
 c:=GetAbilitycost(pl,num);
 if emulation=false then
  inc(players[curplayer].manaspend,c);
 dec(players[curplayer].mana,c);
 if (c=0)and(gamelogic[threadnum].aiinfo.thinking)and(gamelogic[threadnum].PlayersInfo[curplayer].control=1) then
  dec(cureff,200);

 if (num>0)and(cardinfo[n].abilityrequiretarget)and(emulation=false) then
 begin
  if n in [103] then
   EFF_MoveCreatureToSlot(curPlayer,num,side2,num2,1)
  else if n in [17,32,34,98,107,159] then
   EFF_MoveCreatureToSlot(curPlayer,num,side2,num2,2)
  else
   EFF_MoveCreatureToSlot(curPlayer,num,side2,num2,3);
 end else
 if (n<>66)and(n<>-3) then
  creatureact(curplayer,num);
// ForceLogmessage('Ab3');
 if not emulation then EFF_AbilityUsed(curplayer,n,target,false);
 if (n<>66)and(emulation=false) then
 begin
  if num>0 then
   ShowMes(cardinfo[n].name+' ^uses ability')
  else
   ShowMes(playername(curplayer)+'^ ^uses^ '+cardinfo[-3].name)
 end;
 if not emulation then EFF_AbilityUsed(curplayer,n,target,true);
 if num>0 then
  ActingCreature:=pl*10+num;

 case n of
  {Mana Storm}
  -3:begin
      actingcreature:=0;
      MassDamage(pl,0,cardinfo[n].logicparam,3,0);
      ChangePower(pl,-2,true);
      GetCard(pl);
      if (gamelogic[threadnum].aiinfo.thinking) then
      begin
       if numaction=gamelogic[threadnum].duel.numaction+1 then
        inc(cureff,(players[curplayer].mana)*400);
      end;
     end;
  {Unholy Monument}
  1:begin
     if emulation then
     begin
      if (side2<>pl) then
       dec(cureff,10);
     end;
     BurstAttack(side2,num2,cardinfo[n].logicparam);
    end;
  {Gobln Pyromancer}
  2:begin
     DealDamage(pl,num,side2,num2,cardinfo[n].logicparam,2,true);
    end;
  {Orc Trooper}
  5:begin
     GetSpecificCard(pl,5,5,pl*10+num);
    end;
  {Dragon}
  15:begin
      for q:=1 to 6 do if q<>num2 then
       DealDamage(pl,num,side2,q,cardinfo[15].logicparam2,2,false,true);
      DealDamage(pl,num,side2,num2,cardinfo[15].logicparam,2,true,true);
      CheckDelayedEffects;
     end;
  {Templar}
  19:begin
      BurstAttack(pl,num,-cardinfo[n].logicparam);
      GetCard(pl,true,0,pl*10+num);
     end;
  {Crusader,Elven Scout, Devourer}
  17,32,103:
     begin
      if emulation then
       dec(cureff,100);

      cr:=players[side2].creatures[num2];
      players[side2].creatures[num2]:=players[pl].creatures[num];
      players[pl].creatures[num]:=cr;
     end;
  {Leprechaun}
  31:begin
      r:=0;
      if (num>1)and(players[pl].creatures[num-1].cardnum<>0) then
       r:=r+HealCreature(pl,num,pl,num-1,cardinfo[n].logicparam,false,false);
      if (num<6)and(players[pl].creatures[num+1].cardnum<>0) then
       r:=r+HealCreature(pl,num,pl,num+1,cardinfo[n].logicparam,false,false);
      if r>0 then
       ShowMes(cardinfo[31].name+' ^heals %1 life to neighboring creatures%%'+inttostr(cardinfo[n].logicparam));
     end;
  {Dryad}
  34:begin
      burstattack(pl,num,1,true);
      if getattack(pl,num)>=6 then
       getcard(pl,true,34,pl*10+num);
      end;
  {Elven Bard}
  36:begin
      CreatureAttacks(side2,num2,3-pl);
     end;
  {Forest Sprite, Elven Lord,Elven Archer, Soul Hunter}
  16,37,38,56:begin
               DealDamage(pl,num,side2,num2,cardinfo[n].logicparam,2,true);
              end;
  {Faerie Mage}
  40:begin
      DealDamage(pl,num,3-pl,0,players[pl].spellpower,2,true);
     end;
  {Ancient Zubr}
  41:begin
      burstattack(pl,num,1,true);
      if emulation=false then
       showmes('^Attack of %1 increases by 1 permanently%%'+cardinfo[n].name);
     end;
  {Archivist}
  43:begin
      GetCard(pl,true,0,pl*10+num);
     end;
  {Adept of Darkness}
  49:begin
      if emulation then
       dec(cureff,2000);
      r:=players[side2].creatures[num2].cardnum;
      CreatureDies(side2,num2);
      if r=85 then
       DuelDelay(250);
      AddMana(pl,cardinfo[n].logicparam{$ifndef aitesting},cardinfo[49].name+' ^generates %1 mana for its owner%%'+inttostr(cardinfo[n].logicparam){$endif});
     end;
  {Vampire Mystic}
  54:begin
      DealDamage(pl,num,side2,num2,cardinfo[n].logicparam2,2,true);
     end;
  {Vampire Elder}
  57:begin
      r:=MassDamage(pl,num,cardinfo[n].logicparam,2,0);
      if (emulation=false)and(r>0) then
       ShowMes(cardinfo[57].name+' ^deals %1 damage to opponent''s creatures%%'+inttostr(cardinfo[n].logicparam));
      CheckDelayedEffects;
     end;
  {Insanian Wizard}
  61:begin
      q:=players[side2].creatures[num2].cardnum;
      players[side2].creatures[num2].cardnum:=-2;
      players[side2].creatures[num2].life:=2;
      players[side2].creatures[num2].counter:=0;
      players[side2].creatures[num2].bonus:=0;
      players[side2].creatures[num2].abilitywas:=false;
      if emulation=false then
      begin
       EFF_CreatureReplaced(side2,num2);
       ShowMes(cardinfo[q].name+' ^is polymorphed to sheep');
      end;
      GetCard(pl,true,0,pl*10+num);
     end;
  {Orc Shaman}
  62:begin
      DealDamage(pl,num,3-pl,0,cardinfo[n].logicparam,2,true);
     end;
  {Bastion of Order}
  64:begin
      q:=players[side2].creatures[num2].cardnum;
      DealDamage(pl,num,side2,num2,cardinfo[n].logicparam,2,false,true);
      DealDamage(pl,num,pl,num,cardinfo[n].logicparam2,2,false,true);
      if emulation=false then
       ShowMes(cardinfo[64].name+' ^deals %1 damage to %2 and to self%%'+inttostr(cardinfo[n].logicparam)+'%%'+cardinfo[q].name);
      CheckDelayedEffects;
     end;
  {Elven Cavalry}
  66:begin
//      MarkCreature(pl,num);
      CreatureAttacks(pl,num,3-pl);
     end;
  {Lazy Ogre}
  69:begin
      burstattack(pl,num,cardinfo[n].logicparam,false,true);
     end;
  {Witch Doctor}
  71:begin
      AddLife(pl,cardinfo[n].logicparam{$ifndef aitesting},cardinfo[71].name+' ^heals %1 life to %2`pl%%'+inttostr(cardinfo[n].logicparam)+'%%'+playername(pl)+'`pl'{$endif});
     end;
  {Vampire Priest}
  78:begin
      Addlife(pl,cardinfo[n].logicparam2{$ifndef aitesting},''{$endif});
      DealDamage(pl,num,side2,num2,cardinfo[n].logicparam,2,true);
     end;
  {Banshee}
  79:begin
      CreatureDies(pl,num2);
      CreatureAct(pl,num);
      MassDamage(pl,num,cardinfo[n].logicparam,2,0);
      if emulation=false then
       ShowMes(cardinfo[79].name+' ^deals %1 damage to opponent''s creatures%%'+inttostr(cardinfo[n].logicparam));
      CheckDelayedEffects;
     end;
  {Glory Seeker}
  90:begin
      CreatureDies(side2,num2);
      if (emulation)and(side2=pl) then
       dec(cureff,10000);
     end;
  {Harpy}
  81:begin
      ChangePower(3-pl,-1,false{$ifndef aitesting},cardinfo[81].name+' ^decreases opponent''s spell power by %1%%1'{$endif});
     end;
  {Air Elemental}
  82:begin
      CreatureReturns(side2,num2,side2);
     end;
  {Fire Elemental}
  83:begin
      s1:=cardinfo[players[side2].creatures[num2].cardnum].name;
      s2:=cardinfo[players[3-side2].creatures[num2].cardnum].name;
      DealDamage(pl,num,side2,num2,cardinfo[n].logicparam,2,false,true);
      DealDamage(pl,num,3-side2,num2,cardinfo[n].logicparam2,2,false,true);
      if emulation=false then
       ShowMes(cardinfo[83].name+' ^deals %1 damage to %2 and to %3%%'+inttostr(cardinfo[n].logicparam)+'%%'+s1+'%%'+s2);
      CheckDelayedEffects;
     end;
  {Metamorph}
  84:begin
      q:=getAttack(side2,num2);
      burstattack(pl,num,q-getattack(pl,num),true);
      inc(players[pl].creatures[num].counter,players[pl].creatures[num].bonus);
      players[pl].creatures[num].bonus:=0;
     end;
  {Temple Warrior}
  88:begin
      BurstAttack(side2,num2,cardinfo[n].logicparam,false,true);
      DealDamage(pl,num,pl,num,cardinfo[n].logicparam2,-1,true);
      if (emulation)and(side2<>pl) then
       dec(cureff,10);
     end;
  {Preacher}
  92:begin
      r:=getattack(side2,num2);
      BurstAttack(side2,num2,r,false,true);
     end;
  {Elven Dancer}
  98:begin
      cr:=players[pl].creatures[num];
      players[pl].creatures[num]:=players[pl].creatures[num2];
      players[pl].creatures[num2]:=cr;
      if emulation then
       dec(cureff,200);
     end;
  {Mummy}
  99:begin
      q:=players[side2].creatures[num2].cardnum;
      w:=DealDamage(pl,num,side2,num2,cardinfo[n].logicparam,2,false,true);
      AddLife(pl,cardinfo[n].logicparam2{$ifndef aitesting},''{$endif});
      if emulation=false then
       ShowMes(cardinfo[n].name+' ^deals %1 damage to %2 and heals owner%%'+inttostr(w)+'%%'+cardinfo[q].name);
      CheckDelayedEffects;
     end;
  {Ergodemon}
  100:begin
       players[pl].creatures[num2].life:=0;
       checkondie;
       BurstAttack(pl,num,cardinfo[n].logicparam2);
       HealCreature(pl,num,pl,num,cardinfo[n].logicparam,true,false);
      end;
  {Cultist}
  101:begin
       CreatureDies(pl,num2);
{       players[pl].creatures[num2].life:=0;
       checkondie;}
       ChangePower(pl,1,false{$ifndef aitesting},cardinfo[101].name+' ^increases owner''s spell power by %1%%1'{$endif});
      end;
  {Ghoul}
  104:begin
       DealDamage(pl,num,side2,num2,cardinfo[n].logicparam,2,true);
       HealCreature(pl,num,pl,num,cardinfo[n].logicparam2,true,false);
      end;
  {Fire Drake}
  107:begin
       cr:=players[side2].creatures[num2];
       players[side2].creatures[num2]:=players[pl].creatures[num];
       players[pl].creatures[num]:=cr;
       w:=0;
       for q:=1 to 6 do
       if players[3-side2].creatures[q].cardnum<>0 then
        inc(w,DealDamage(side2,num2,3-side2,q,cardinfo[n].logicparam,2,false,true));
       for q:=1 to 6 do
       if (q<>num2)and(players[side2].creatures[q].cardnum<>0) then
        inc(w,DealDamage(side2,num2,side2,q,cardinfo[n].logicparam,2,false,true));
       if w>0 then
       begin
        creatureact(side2,num2);
        if emulation=false then
         ShowMes(cardinfo[107].name+' ^deals %1 damage to each other creature%%3');
        CheckDelayedEffects;
       end;
      end;
  {Prophet}
  110:begin
       Changepower(pl,-1,false{$ifndef aitesting},cardinfo[n].name+' ^decreases owner''s spell power by %1%%1'{$endif});
       GetCard(pl,true,0,pl*10+num);
      end;
  {Gryphon}
  113:begin
       CreatureReturns(pl,num,pl);
      end;
  {Gluttonous Zombie}
  116:begin
       DealDamage(pl,num,side2,num2,cardinfo[116].logicparam,2,true);
       if (emulation)and(side2=pl) then
        dec(cureff,10000);
      end;
  {Harbringer}
  117:begin
       w:=players[pl].numhandcards;
       players[pl].numhandcards:=0;
       if emulation=false then
        EFF_LoseAllCards(pl);
       for q:=1 to w do
        GetCard(pl,true);
      end;
  {Balance Keeper}
  121:begin
//       AddLife(pl,players[3-pl].life-players[pl].life{$ifndef aitesting},'default'{$endif});
      DealDamage(pl,num,3-pl,0,cardinfo[121].logicparam,2,true);
      if emulation=false then
       Signal('Sound\Play\PositiveEffect');
      AddLife(pl,cardinfo[121].logicparam2{$ifndef aitesting},'default'{$endif});
      end;
  {Phoenix}
  131:begin
       MassDamage(pl,num,cardinfo[n].logicparam,2,0);
       if emulation=false then
        ShowMes(cardinfo[131].name+' ^deals %1 damage to opponent''s creatures%%'+inttostr(cardinfo[n].logicparam));
       if players[pl].creatures[num].cardnum<>0 then
        CreatureReturns(pl,num,pl);
       CheckDelayedEffects;
      end;
  {Monk}
  132:begin
       BurstAttack(side2,num2,cardinfo[n].logicparam2,false);
       HealCreature(pl,num,side2,num2,cardinfo[n].logicparam,true,false);
      end;
  {Ascetic}
  133:begin
       LoseCard(pl,1);
       ChangePower(pl,2,false{$ifndef aitesting},cardinfo[133].name+' ^increases owner''s spell power by %1%%2'{$endif});
{       if emulation=false then
        fillchar(cardsxy,sizeof(cardsxy),0);}
      end;
  {Familiar}
  140:begin
       GetCard(pl,true,0,pl*10+num);
       GetCard(pl,true,0,pl*10+num);
       CreatureDies(pl,num);
      end;
  {Zealot}
  143:begin
       for q:=-1 to 1 do
       if (q<>0)and(num+q>=1)and(num+q<=6)and(players[pl].creatures[num+q].cardnum=0) then
       begin
        PlaceCreature(pl,num+q,143);
        if emulation=false then
        begin
         Signal('Sound\Play\PositiveEffect');
         creatureact(pl,num+q);
         ShowMes('New Zealot is summoned');
        end;
       end;
      end;
  {Elven Hero}
  144:begin
       for q:=1 to 6 do
       if (abs(q-num)<=1)and(winner=0)and(players[pl].creatures[q].cardnum<>0) then
       begin
        CreatureAttacks(pl,q,3-pl);
       end;
     end;
  {Cursed Soul}
  146:begin
       for q:=-1 to 1 do
       if (q<>0)and(num+q>=1)and(num+q<=6)and(players[pl].creatures[num+q].cardnum<>0)and(players[pl].creatures[num+q].cardnum<>146) then
       begin
        w:=players[pl].creatures[num+q].cardnum;
        players[pl].creatures[num+q].cardnum:=146;
        players[pl].creatures[num+q].life:=cardinfo[146].life;
        players[pl].creatures[num+q].counter:=0;
        players[pl].creatures[num+q].bonus:=0;
        players[pl].creatures[num+q].abilitywas:=false;
        if emulation=false then
        begin
         EFF_CreatureReplaced(pl,num+q);
         markcreature(pl,num+q);
         ShowMes(cardinfo[w].name+' ^is transformed to %1%%Cursed Soul');
        end;
       end;
      end;
  {Warlock}
  147:begin
       BurstAttack(pl,num,-cardinfo[n].logicparam,true);
       GetCard(pl,true,0,pl*10+num);
      end;
  {Greater Demon}
  148:begin
       DealDamage(pl,num,side2,num2,cardinfo[n].logicparam,2,true);
       CreatureAct(pl,num);
       MassDamage(pl,num,cardinfo[n].logicparam2,2,0);
       if emulation=false then
        ShowMes(cardinfo[148].name+' ^deals %1 damage to opponent''s creatures%%'+inttostr(cardinfo[n].logicparam2));
       CheckDelayedEffects;
      end;
  {Energy mage}
  158:begin
       if emulation then
        dec(cureff,10);
       AddMana(pl,cardinfo[158].logicparam{$ifndef aitesting},cardinfo[158].name+' ^generates %1 mana for its owner%%'+inttostr(cardinfo[158].logicparam){$endif});
     end;
  {Water Elemental}
  159:begin
       cr:=players[side2].creatures[num2];
       players[side2].creatures[num2]:=players[pl].creatures[num];
       players[pl].creatures[num]:=cr;
       CreatureAttacks(pl,num2,3-pl);
      end;
  {Elf Summoner}
  160:begin
       PlaceCreature(pl,num2,159);
       if emulation=false then
       begin
        Signal('Sound\Play\PositiveEffect');
        ShowMes('New Assault Snake is summoned');
       end;
      end;
  {Tentacle Demon}
  161:begin
       if emulation=false then
        EFF_MoveCreatureToSlot(side2,num2,side2,num,2);
       cr:=players[side2].creatures[num2];
       players[side2].creatures[num2]:=players[side2].creatures[num];
       players[side2].creatures[num]:=cr;
      end;
 end;
 CheckOnDie;
 ActingCreature:=0;
 if emulation=false then
 begin
  waitAnimation;
  SuspendedDelay(300);
 end;
 if (winner=0)and(num>0) then
 for q:=1 to 6 do
 begin
  case players[pl].creatures[q].cardnum of
   {Priest of Fire}
   11:begin
       DuelDelay(50);
       CreatureAct(pl,q);
       MassDamage(pl,q,cardinfo[11].logicparam,2,1);
       if emulation=false then
        ShowMes(cardinfo[11].name+' ^deals %1 damage%%'+inttostr(cardinfo[11].logicparam));
       CheckDelayedEffects;
       SuspendedDelay(150);
       CheckOnDie;
//       DealDamage(pl,q,3-pl,0,3,2,true);
      end;
   {Knight of Darkness}
   52:begin
       DuelDelay(50);
       MarkCreature(pl,q);
       burstattack(pl,q,2,true);
       SuspendedDelay(150);
      end;
   {Hierophant}
   111:begin
        DuelDelay(50);
        CreatureAct(pl,q);
        Changepower(pl,1,false{$ifndef aitesting},cardinfo[111].name+' ^increases owner''s spell power by %1%%1'{$endif});
        SuspendedDelay(200);
       end;
  end;
 end;
 CheckOnDie;
 if winner>0 then
  exit;
 CheckEndTurn;
end;

procedure tduel.UseCard(num,target:integer);
var q,w,e,r,el,n,pl,oldslot:integer;
    s:string;
begin
 try
 if emulation=false then
 begin
  ForceLogMessage('UseCard, hash='+inttostr(getPlayerHash(curplayer)));
  ActivateCard(0);
 end;
 inc(numaction);

 n:=players[curplayer].handcards[num];

 {$ifndef aitesting}
 if (emulation=false)and(gamelogic[threadnum].playersinfo[curplayer].control<>0)and(curplayer<>1) then
  ShowCardInfo(n,num,target);
 {$endif}

 if emulation=false then
 begin
  s:=cardinfo[n].name;
  for q:=1 to length(s) do if s[q]=' ' then s[q]:='_';
//  Signal('CardUsed['+s+']');
 end;
 if emulation=false then
  inc(players[curplayer].manaspend,getcost(curplayer,n));
 dec(players[curplayer].mana,getcost(curplayer,n));
 if (players[curplayer].mana=0)and(gamelogic[threadnum].aiinfo.thinking)and(gamelogic[threadnum].PlayersInfo[curplayer].control=1) then
  dec(cureff,(players[curplayer].spellpower+1)*200);
 if emulation=false then
  lockdrawing;
 for q:=num+1 to players[curplayer].numhandcards do players[curplayer].handcards[q-1]:=players[curplayer].handcards[q];
 dec(players[curplayer].numhandcards);
 if emulation=false then
 begin
  LeaveDrawing;
{  if (cardinfo[n].life=0)and(cardinfo[n].requiretarget=false) then
  begin
   castedcard.card:=n;
   castedcard.endpos.x:=0;
   castedcard.endpos.y:=0;
   castedcard.startpos:=cardpos(curplayer,num);
   castedcard.startspeed.Y:=(curplayer*2-3)*(9+(num-1) div 2);
   castedcard.startspeed.X:=35-(num-1)*4;
   castedcard.starttime:=MyTickCount;
  end;}
  if cardinfo[n].life=0 then
  begin
   s:='^ ^casts %1%%';
//   Signal('sound\play\SpellCasted');
   EFF_CastSpell(curplayer,num,target,n);
  end else
  begin
   s:='^ ^summons %1%%';
//   Signal('sound\play\CreatureSummoned');
   EFF_PlaceCreature(curPlayer,num,target);
  end;
  ShowMes((playername(curplayer))+s+cardinfo[n].name);
 end;
 if emulation=false then
  lockdrawing;
 if cardinfo[n].life>0 then
 begin
  q:=abs(target);
  oldslot:=players[curplayer].creatures[q].cardnum;
  PlaceCreature(curplayer,q,n);
  if emulation=false then
   LeaveDrawing;
  CreatureComes(curplayer,q,oldslot);
  if winner>0 then
   exit;
 end else
 begin
  if emulation=false then
   LeaveDrawing;
  SpellCasted(curplayer,n,target);
 end;
 if winner>0 then
  exit;

 lastcardcomment:=0;
 if Emulation=false then
  MouseCheck;
 except
  on e:Exception do ForceLogMessage('Error in card using - '+e.Message);
  else ForceLogMessage('Except in use card');
 end;
 CheckEndTurn;
end;

function tDuel.NeedEndTurn:boolean;
var q:integer;
begin
 result:=false;
 if (wasreplace=false)and(gamelogic[threadnum].PlayersInfo[curplayer].noreplace=false)and(players[curplayer].numhandcards>0) then
  exit;
 for q:=1 to players[curplayer].numhandcards do
 if CanUseCard(q) then
  exit;
 for q:=1 to 6 do if CanUseAbility(q) then
  exit;
 if (players[curplayer].numhandcards=0)and(players[curplayer].spellpower>=2)and(players[curplayer].mana>=2) then
  exit;
 if winner>0 then
  exit;
 result:=true;
end;

procedure tDuel.CheckEndTurn;
var q:integer;
begin
 {$IFNDEF SERVER}{$IFNDEF AITESTING}
 if (gamelogic[threadnum].playersinfo[curplayer].control=0)and(optinfo.AutoEndTurn)and(needendturn)and(canendturn) then
 begin
  if (gamelogic[threadnum].playersinfo[curplayer].control=0)and(gamelogic[threadnum].playersinfo[3-curplayer].control=-1) then
  begin
   canendturn:=false;
   LogicInfo.AddAction(0)
  end else
  begin
   DuelDelay(300);
   EndTurn;
  end;
 end;
{$ENDIF}{$ENDIF}
end;

function tDuel.HealCreature(side1,num1,side2,num2,value:integer;needmes,needcreatureact:boolean):integer;
var q,w,e,c:integer;
begin
 c:=players[side2].creatures[num2].cardnum;
 e:=cardinfo[c].life-players[side2].creatures[num2].life;
 if value>e then
  value:=e;
 result:=value;
 if value=0 then exit;
 inc(players[side2].creatures[num2].life,value);
 {$ifndef AITESTING}
 if emulation=false then
 begin
  signinfo.AddSign(side2,num2,value);
  if needcreatureact then
   creatureact(side1,num1);
  if needmes then
  begin
   if num1=0 then
    ShowMes(cardinfo[ActingSpell].name+' ^heals %1 life to %2%%'+inttostr(value)+'%%'+cardinfo[c].name)
   else
   begin
    if (side1=side2)and(num1=num2) then
     ShowMes(cardinfo[c].name+' ^heals %1 life to self%%'+inttostr(value))
    else
     ShowMes(cardinfo[players[side1].creatures[num1].cardnum].name+' ^heals %1 life to %2%%'+inttostr(value)+'%%'+cardinfo[c].name)
   end;
  end;
 end;
 {$endif}
end;

procedure tDuel.BurstAttack(pl,num,value:integer;permanent:boolean=false;needmes:boolean=false);

 procedure MakeChanges(n:integer);
 begin
  if (permanent=false) then
   inc(players[pl].creatures[num].bonus,n)
  else
   inc(players[pl].creatures[num].counter,n);
 end;

begin
 if (players[pl].creatures[num].cardnum=86)and(value>0) then
  permanent:=true;
 makechanges(value);
 if emulation=false then
  signinfo.AddSign(pl,num+10,value);
 if getAttack(pl,num)=0 then
 begin
  while getAttack(pl,num)<1 do
   MakeChanges(1);
  MakeChanges(-1);
 end;

 {This code is required to fix "Goblin Chieftain + Warlock" issue}
 while getAttack(pl,num)<value do
  MakeChanges(1);

 {$ifndef AITESTING}
 if (emulation)and(players[pl].creatures[num].new) then
  dec(cureff,5);
 if needmes then
 if permanent then
  ShowMes('Attack of %1 is increased by %2%%'+cardinfo[players[pl].creatures[num].cardnum].name+'%%'+inttostr(value))
 else
  ShowMes('Attack of %1 is temporarily increased by %2%%'+cardinfo[players[pl].creatures[num].cardnum].name+'%%'+inttostr(value));
 {$endif}
end;

function tDuel.ChangePower(pl,value:integer;manastorm:boolean=false{$ifndef aitesting};mes:string=''{$endif}):boolean;
var q,w,qq,r:integer;
begin
 r:=players[pl].spellpower;
 inc(players[pl].spellpower,value);
 if players[pl].spellpower<0 then
  players[pl].spellpower:=0;
 result:=players[pl].spellpower<>r;

 {$ifndef aitesting}
 signinfo.AddSign(pl,-1,value);
 if not emulation then
 if value>0 then
  EFF_PlayerEffect(pl,plrEffGainPower,value)
 else
  EFF_PlayerEffect(pl,plrEffLosePower,value);
 if (result)and(mes<>'')and(emulation=false) then
  ShowMes(mes);
 {$endif}

 if (result)and(value<0)and(manastorm=false) then
 begin
  {Witch Doctor}
  for q:=1 to 6 do if players[3-pl].creatures[q].cardnum=71 then
  begin
   DuelDelay(100);
   CreatureAct(3-pl,q);
   ChangePower(3-pl,1,false{$ifndef aitesting},cardinfo[71].name+' ^increases owner''s spell power by %1%%1'{$endif});
   SuspendedDelay(300);
  end;

  {Reaver}
  for qq:=1 to 2 do
  begin
   if qq=1 then w:=curplayer else w:=3-curplayer;
   for q:=1 to 6 do if players[w].creatures[q].cardnum=50 then
   begin
    DuelDelay(100);
    CreatureAct(w,q);
    GetCard(w,true,50,w*10+q);
   end;
  end;
 end;
end;

procedure tDuel.Replacecard;
var q,w:integer;
begin
 if emulation=false then
 begin
  ForceLogMessage('ReplaceCard, hash='+inttostr(getPlayerHash(curplayer)));
  ActivateCard(0);
  lockdrawing;
 end;
 wasreplace:=true;
 inc(numaction);
 dec(players[curplayer].numhandcards);
 for q:=num to players[curplayer].numhandcards do
  players[curplayer].handcards[q]:=players[curplayer].handcards[q+1];
 if emulation=false then
 begin
  EFF_LoseHandCard(curPlayer,num);
 end;
 if emulation=false then
  leavedrawing;
 GetCard(curplayer,true,0,0,false,true,true);
 CheckEndTurn;
end;

procedure tDuelSave.ImportData;
begin
 saveDuel:=gamelogic[threadnum].Duel;
 SavePlayersInfo[1]:=gamelogic[threadnum].Playersinfo[1];
 SavePlayersInfo[2]:=gamelogic[threadnum].Playersinfo[2];
end;

procedure tDuelSave.ExportData;
begin
 SaveDuel.threadnum:=threadnum;
 gamelogic[threadnum].Duel:=SaveDuel;
 gamelogic[threadnum].PlayersInfo[1]:=SavePlayersinfo[1];
 gamelogic[threadnum].PlayersInfo[2]:=SavePlayersinfo[2];
end;

function tAiInfo.Emulation:boolean;
begin
 result:=thinking or combating;
end;

function tduel.Emulation:boolean;
begin
 {$ifdef server}
 result:=true;
 {$else}
 {$ifdef aitesting}
 result:=true;
 {$else}
 result:=gamelogic[threadnum].AiInfo.emulation;
 {$endif}
 {$endif}
end;

function tduel.getPlayerHash(pl:integer):integer;
var q:integer;
begin
 result:=integer(players[pl].life)*1000000-integer(players[3-pl].life)*10000;
 inc(result,integer(players[pl].spellpower)*1000-integer(players[3-pl].spellpower)*10);
 for q:=1 to 6 do
 if players[pl].creatures[q].cardnum<>0 then
 begin
  inc(result,integer(players[pl].creatures[q].cardnum)*(20+q));
  inc(result,integer(players[pl].creatures[q].life)*(200+q));
 end;
 for q:=1 to 6 do
 if players[3-pl].creatures[q].cardnum<>0 then
 begin
  dec(result,integer(players[3-pl].creatures[q].cardnum)*(80+q));
  dec(result,integer(players[3-pl].creatures[q].life)*(800+q));
 end;
{ for q:=1 to players[pl].numhandcards do
  inc(result,(100000+q)*players[pl].handcards[q]);
 for q:=1 to 30 do
  inc(result,(3+q)*gamelogic[threadnum].playersinfo[pl].curdeck.cards[q]);}
end;

procedure tduel.DuelDelay(time:integer);
begin
 {$ifndef server}
 {$ifndef aitesting}
 if gamelogic[threadnum].AiInfo.emulation=false then
 begin
  Sleep(time+SuspendedDelayTime);
  SuspendedDelayTime:=0;
 end;
 {$endif}
 {$endif}
end;

procedure tduel.SuspendedDelay(time:integer);
begin
 {$ifndef server}
 {$ifndef aitesting}
 SuspendedDelayTime:=time;
 {$endif}
 {$endif}
end;

function tduel.PlayerName(n:integer):string;
begin
 result:=gamelogic[threadnum].playersinfo[n].Name;
end;

begin
 mainDuel:=@gameLogic[0].duel;
end.
