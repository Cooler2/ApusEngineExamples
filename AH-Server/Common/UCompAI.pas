// Author: Alexey Stankevich (Apus Software)
unit UCompAI;
interface
uses Ulogic,SysUtils,Cnsts,UCardGens;
const {$ifndef aitesting}checkabilities=true;{$else}checkabilities={true;}false;{$endif}
      maxserverAIwidth:integer=2000;
      {$ifdef server}needAiStrings=false;{$else}{$ifdef aitesting}needAiStrings=false;{$else}needaistrings=true;{$endif}{$endif}

type  tPairPower=array[1..maxcardgen,1..maxcardgen] of shortint;
      tindividualpower=array[1..numcards] of smallint;
var   pairpower,PairPowerPl,pairpowerM,draftpower,draftpowerpl,basispair:tPairPower;
      ZeroGens,HandGensCommon,CreatureGensCommon,HandGensDraft,CreatureGensDraft,enemyCreatureGensDraft:tCardGens;

procedure FindBestAction(var action:tAIAction;thread:shortint=0;evaluationplayer:integer=0);
//procedure PairPowerLoad;
procedure PairPowerLoad;
procedure PairPowerPlSave(filename:string);
procedure MergePairPowers;

implementation

uses myservis,UOutput,UCampaignlogic;
var maxchecked:integer;
    needstrings:boolean;
    lifepointseff:array[0..50] of integer;
    crpointseff:array[0..50] of integer;

procedure PairPowerPlSave(filename:string);
var f:file of tPairPower;
begin
 assign(f,filename);
 rewrite(f);
 write(f,PairPowerPl);
 close(f);
end;

procedure PairPowerExtLoad(var p:tpairpower;filename:string);
var f:file of tPairPower;
begin
 if fileexists(filename)=false then
  forcelogmessage('AI file not found: '+filename);
 assign(f,filename);
 reset(f);
 read(f,p);
 close(f);
end;

procedure MergePairPowers;
var q,w,e:integer;

function wasmodified(n:integer):boolean;
begin
 result:=n in [2,11,31,34,52,55,59,65,81,82,85,87,92,94,96,101,{113,}115,119,123,145];
end;

begin
 for q:=1 to numcards do
 for w:=1 to numcards do
 if wasmodified(q) or wasmodified(w) then
  pairpowerpl[q,w]:=pairpowerm[q,w]
 else
  pairpowerpl[q,w]:=pairpower[q,w];
 PairPowerPlSave('Inf\PairPowerMerged.inf');
end;

procedure BuildLifePointsEff;
var q,w:integer;
begin
 w:=0;
 for q:=0 to 50 do
 begin
  case q of
   1..5:inc(w,1150);
   6..10:inc(w,1000);
   11..15:inc(w,840);
   16..20:inc(w,600);
   21..25:inc(w,530);
   26..30:inc(w,240);
   31..40:inc(w,140);
   41..50:inc(w,70);
  end;
  lifepointseff[q]:=w;
 end;
end;

procedure BuildCrPointsEff(n1,n2,n3,n4,n5,n6:integer);
var q,w:integer;
begin
 for q:=0 to 50 do
 begin
  case q of
   0..3:w:=n1*10+(n2-n1)*10*q div 4;
   4..7:w:=n2*10+(n3-n2)*10*(q-4) div 4;
   8..11:w:=n3*10+(n4-n3)*10*(q-8) div 4;
   12..16:w:=n4*10+(n5-n4)*10*(q-12) div 5;
   17..24:w:=n5*10+(n6-n5)*10*(q-17) div 8;
   else
    w:=n6*10+(q-25)*40;
  end;
  CrpointsEff[q]:=w;
 end;
end;

procedure PairPowerLoad;
var q,w:integer;
begin
 PairPowerExtLoad(pairpower,'Inf\pairpower.inf');
 PairPowerExtLoad(draftpower,'Inf\draftpower.inf');

 {$ifndef server}{$ifdef aitesting}
 PairPowerExtLoad(pairpowerm,'Inf\pairpowerm.inf');
 PairPowerExtLoad(draftpowerpl,'Inf\pairpowerdr.inf');
 PairPowerExtLoad(basispair,'Inf\basispower.inf');
 {$endif}{$endif}

 ClearGens(ZeroGens);
 LoadCardGensFromFile(HandGensCommon,'Inf\handgenscommon.inf');
 LoadCardGensFromFile(CreatureGensCommon,'Inf\creaturegenscommon.inf');
 LoadCardGensFromFile(HandGensDraft,'Inf\handgensdraft.inf');
 LoadCardGensFromFile(CreatureGensDraft,'Inf\creaturegensdraft.inf');
 LoadCardGensFromFile(enemyCreatureGensDraft,'Inf\enemycreaturegensdraft.inf');

 BuildLifePointsEff;
 BuildCrPointsEff(68,100,139,171,209,251);
end;

procedure FindBestAction;
var bestaction,curaction:TAIAction;
    AiString:string;
    aiduel,tmpduel:tduel;
    oldInfo:TAiInfo;
    lasteff:integer;
    q,w,e,r,t:integer;
    LastChecked,LastAdded:integer;
    curdiff,aiplayer:integer;
    s:string;
    AIHandGens,AICreatureGens,EnemyCreatureGens:pCardGens;

function cardweight(v:integer):integer;
begin
 case v of
  1:result:=4500;
  2:result:=4250;
  3:result:=4000;
  4:result:=3250;
  5:result:=3000;
  else
   result:=2400;
 end;
end;

function getpair(q,w:integer):integer;
var p:integer;
begin
 {$ifdef aitesting}
 result:=gamelogic[thread].playersinfo[aiplayer].pairgens[q,w];
 gamelogic[thread].playersinfo[aiplayer].pairgensused[q,w]:=1;
 {$else}
 result:=0;
 {$endif}
end;


function GetCardEff(pl,num:integer):integer;
var c,cost,p,pp,ppp,q,w,e,r:integer;
begin
 if pl<>aiplayer then
  result:=100
 else
 with AIDuel.players[pl] do
 begin
  p:=spellpower;
  if p<1 then
   p:=1
  else
  if p>10 then
   p:=10;
  c:=handcards[num];
  cost:=cardinfo[c].cost;
  if p<=cost then
  begin
   result:=cardinfo[c].power1;
   if cost>1 then
    inc(result,(p-1)*(cardinfo[c].powercost-cardinfo[c].power1) div (cost-1));
  end else
  begin
   result:=cardinfo[c].powercost+(p-cost)*(cardinfo[c].power10-cardinfo[c].powercost) div (10-cost)
  end;

  if cardinfo[c].special=false then
  begin
   p:=0;
   pp:=0;
   ppp:=0;
   for q:=1 to numhandcards do
   if (q<>num)and(cardinfo[handcards[q]].special=false) then
   begin
{    if gamelogic[thread].playersinfo[AiPlayer].control=13 then
     inc(p,getpair(c,handcards[q])*10)
    else} if gamelogic[thread].playersinfo[AiPlayer].control=16 then
     inc(p,pairpowerm[c,handcards[q]]*10)
    else
     inc(p,pairpower[c,handcards[q]]*10);
   end;
   for q:=1 to 6 do
   begin
    w:=creatures[q].cardnum;
    if (w>0)and(cardinfo[w].ignoreforhand=false)and(cardinfo[w].special=false) then
    begin
     e:=cardinfo[w].life;

{     if gamelogic[thread].playersinfo[AiPlayer].control=13 then
      inc(pp,getpair(c,w)*10*(creatures[q].life*4+e*2) div (e*7))
     else}
     if gamelogic[thread].playersinfo[AiPlayer].control=16 then
      inc(pp,pairpowerm[c,w]*10*(creatures[q].life*4+e*2) div (e*7))
     else
      inc(pp,pairpower[c,w]*10*(creatures[q].life*4+e*2) div (e*7));
    end;
   end;
   result:=result*(p*12+pp*9+ppp*3+8000) div 8000;
{   if gamelogic[thread].playersinfo[AiPlayer].control=13 then
    result:=result*(getpair(c,150)+100)div 100
   else}
   if gamelogic[thread].playersinfo[AiPlayer].control>=5 then
    result:=result*(AIHandGens[c]+100)div 100;

   {$ifdef aitesting}
   if gamelogic[thread].playersinfo[AiPlayer].control>=7 then
   begin
    gamelogic[thread].playersinfo[AiPlayer].handgensused[c]:=1;
   end;
   {$endif}
  end;
 end;
end;

function GetEff(pl:integer):integer;
var q,qq,qqq,w,ww,e,r,t,tt,l,s,card,lifetotal,max,el,empty,cc,ee,coin:integer;
begin
 r:=0;
 with AIDuel.players[pl] do
 begin
  if life<=50 then
   r:=lifepointseff[life]
  else
   r:=lifepointseff[50]+(life-50)*25;
  if life>900 then
  begin
   inc(r,-100000+(life-900)*1250);
  end;

//  forcelogmessage('r1='+inttostr(r));

  if gamelogic[thread].playersinfo[AiPlayer].control>=3 then
  begin
   w:=0;
   for q:=1 to spellpower do
   begin
    case q of
     1..6:inc(w,7900-600*q);
     7..12:inc(w,2000-400*(q-10));
     else
      inc(w,1000);
    end;
   end;

   // Опасная штука, может сервер тормозить
   if (needdrafttesting=false)and(gamelogic[thread].playersinfo[AiPlayer].name=campaignmages[19].name) then
    w:=3*w div 5;

   inc(r,w);
   if numhandcards>0 then
   begin
    t:=0;
    for q:=1 to numhandcards do
     inc(t,cardweight(q));
    t:=t div numhandcards;
   // Опасная штука, может сервер тормозить
    if (needdrafttesting=false)and(gamelogic[thread].playersinfo[AiPlayer].name=campaignmages[18].name) then
     t:=t*6 div 5
    else
   // Опасная штука, может сервер тормозить
    if (needdrafttesting=false)and(gamelogic[thread].playersinfo[AiPlayer].name=campaignmages[19].name) then
     t:=t div 2;
    for q:=1 to numhandcards do
    begin
     inc(r,t*(525+getcardeff(pl,q)) div 625);
    end;
   end;
  end else
  begin
   if gamelogic[thread].playersinfo[AiPlayer].control=1 then
    r:=r*2 div 3;
   inc(r,mana*10);
   if pl=AiPlayer then
   begin
    inc(r,spellpower*3000);
    if spellpower>8 then
     dec(r,(spellpower-8)*2500);
    coin:=0;
    for q:=1 to numhandcards do
    if handcards[q]=-1 then
     inc(coin);
    inc(r,numhandcards*1500-coin*900);
   end else
   begin
    inc(r,spellpower*5000);
    inc(r,numhandcards*3000);
   end;
   case gamelogic[thread].playersinfo[AiPlayer].control of
    1:t:=2500;
    2:t:=500;
    else t:=0;
   end;
   if (mana<>spellpower)and(pl=aiplayer) then
   for q:=1 to 6 do {Elven bard,Elven Archer,Ancient Zubr,Archivist,Vampire Mystic,Soul Hunter,Bastion of Order,Elven Cavalry,Witch Doctor,Mummy}
   if (creatures[q].abilitywas=false)and(creatures[q].cardnum in [36,38,41,43,54,56,64,66,71,99])and(mana>=cardinfo[creatures[q].cardnum].abilitycost) then
    t:=0;
   if t>0 then
   begin
    if coin>0 then
     inc(r,t-500);
    if (spellpower=2) and (mana>0) then inc(r,t div 2);
    if (spellpower>=3) and (mana>0) then inc(r,t);
    if (spellpower=5) and (mana>1) then inc(r,t div 2);
    if (spellpower>=6) and (mana>1) then inc(r,t);
    if (spellpower>=8) and (mana>2) then inc(r,t);
   end;
  end;

  {Two Refilled Memory in hand}
  if AiPlayer=pl then
  for q:=1 to numhandcards do if handcards[q]=136 then
  for w:=1 to q-1 do if handcards[w]=136 then
    dec(r,3000);

//  forcelogmessage('r2='+inttostr(r));

  for q:=1 to 6 do if creatures[q].cardnum<>0 then
  begin
   card:=creatures[q].cardnum;
   w:=10*AIDuel.GetAttack(pl,q)+10+cardinfo[card].bonus;
   l:=creatures[q].life;
   if card=161 then
    w:=(w+80) div 2;
   if card=162 then
    l:=l*5;
   if gamelogic[thread].playersinfo[AiPlayer].control<3 then
    e:=100*l+700 else
   begin
    if w>60 then
     w:=60+(w-60)*7 div 10;
    if w>40 then
     w:=40+(w-40)*7 div 10;

    if l>50 then
     e:=crpointseff[50]+(l-50)*35
    else
     e:=crpointseff[l];

    if (card>0)and(card<>146)and(cardinfo[card].ignoreforhand=false)and(cardinfo[card].special=false) then
    begin
     tt:=0;
     for qq:=1 to 6 do
     if (qq<>q) then
     begin
      ww:=creatures[qq].cardnum;
      if (ww>0)and(cardinfo[ww].ignoreforhand=false)and(cardinfo[ww].special=false) then
      begin
       l:=cardinfo[ww].life;

{       if gamelogic[thread].playersinfo[AiPlayer].control=13 then
        inc(tt,getpair(card,ww)*10*(creatures[qq].life*4+l*2) div (l*5))
       else}
       if gamelogic[thread].playersinfo[AiPlayer].control=16 then
        ee:=pairpowerm[card,ww]*10*(creatures[qq].life*4+l*2) div (l*5)
       else
        ee:=pairpower[card,ww]*10*(creatures[qq].life*4+l*2) div (l*5);

       // Корректировка оценки толпы одинаковых существ на поле
       if (ww=card)and(ww<>143) then
       begin
        for qqq:=1 to 6 do
        if (qqq<>q)and(qqq<>qq)and(creatures[qqq].cardnum=ww) then
          ee:=ee*7 div 8
       end;
       inc(tt,ee);
      end;
     end;
{     if (gamelogic[thread].playersinfo[AiPlayer].control=16) then
     begin
      if pl=AiPlayer then
      begin
       if tt>0 then
        tt:=tt*gamelogic[thread].aiinfo.gen3
       else
        tt:=tt*gamelogic[thread].aiinfo.gen4
      end else
       tt:=tt*gamelogic[thread].aiinfo.gen5;
     end else}
     begin
      if pl=AiPlayer then
      begin
       if tt>0 then
        tt:=tt*23
       else
        tt:=tt*45
      end else
       tt:=tt*60;
     end;

     e:=int64(e)*(100000+tt) div 100000;
    end;

    {Orc Trooper}
    if card=5 then
     inc(w,gamelogic[thread].duel.players[pl].spellpower-6);

    {Inquisitor}
    if card=24 then
    begin
     inc(r,(q-4)*10);
     {Armageddon, Planar Burst}
     if AiPlayer=pl then
     begin
      for qq:=1 to numhandcards do
      if (handcards[qq] in [10,130]) then
       inc(w,AIDuel.players[3-pl].hasCreatures*15-10);
     end else
      inc(w,15);
    end;

    {Warlock}
    if card=147 then
     w:=(w*2 div 3)+10;

    {Ascetic}
    if card=133 then
    begin
     dec(w,(gamelogic[thread].duel.players[pl].spellpower-4)*4);
     if w<30 then
      w:=30;
    end;

    {Faerie Mage, Orc Shaman, Elven Cavalry, Prophet}
    if card in [40,62,66,110] then
    begin
     ww:=(spellpower-numhandcards-3)*6;
     if (card in [62,110])and(ww<0) then
      ww:=0
     else if ww<-4 then
      ww:=-4;
     if (AiPlayer=pl)and(card<>110) then
      ww:=ww div 2;
     inc(w,ww);
     if (card=66)and(AiPlayer<>pl)and(aiduel.players[3-pl].creatures[q].life=0)and(gamelogic[thread].duel.players[pl].spellpower>5) then
      inc(w,(gamelogic[thread].duel.players[pl].spellpower-4)*10);
    end;

    {Heretic}
    if card=120 then
    begin
     if AiPlayer=pl then
     begin
      ww:=0;
      for qq:=1 to numhandcards do
      if (handcards[qq]<>0)and(cardinfo[handcards[qq]].element=2) then
       inc(ww,12);
     end else
      ww:=(numhandcards+1)*4;
     ww:=ww+(1-gamelogic[thread].duel.players[pl].spellpower)*3;
     if ww<-5 then
      ww:=-5;
     inc(w,ww);
     if (AiPlayer<>pl)and(aiduel.dueltypenum=1) then
      inc(w,20);
    end;

    if (AiPlayer<>pl)and(gamelogic[thread].playersinfo[AiPlayer].control>=4)and(aiduel.dueltypenum=1) then
    begin
     {Orc Berserker}
     if (card=6)and(creatures[q].life>8) then
     begin
      if AIDuel.players[3-pl].creatures[q].cardnum=0 then inc(w,30) else inc(w,15)
     end;
     {Elven Mystic}
     if (card=65) then
     begin
      inc(w,5+w div 5);
      if (AIDuel.players[3-pl].creatures[q].cardnum=0) then
       inc(w,w*3 div 10);
     end;
     {Priest of Fire, Reaver, Air Elemental}
     if (card=11)or(card=50)or(card=82) then
      inc(w,20);
    end;

    if (AiPlayer=pl)and(gamelogic[thread].playersinfo[AiPlayer].control>=4)and(aiduel.dueltypenum=1) then
    begin
     {Bargul, Treefolk}
     if (card=95)or(card=124) then
      inc(w,15);
    end;
   end;

   {Astral Chaneller}
   if card=155 then
   begin
    if q=1 then dec(w,5) else if creatures[q-1].cardnum=0 then inc(w,10);
    if q=6 then dec(w,5) else if creatures[q+1].cardnum=0 then inc(w,10);
   end;

   {Elf Summoner}
   if card=160 then
   begin
    if q in [3,4] then
     inc(w,1);
    l:=0;
    if q=1 then dec(w,5) else if creatures[q-1].cardnum=0 then inc(l);
    if q=6 then dec(w,5) else if creatures[q+1].cardnum=0 then inc(l);
    if l=1 then inc(w,10);
    if l=2 then inc(w,12);
   end;

   {Leprechaun, Astral Guard}
   if card in [31,72] then
   begin
    if q=1 then dec(w,5) else if creatures[q-1].cardnum<>0 then inc(w,3);
    if q=6 then dec(w,5) else if creatures[q+1].cardnum<>0 then inc(w,3);
   end;

   {Goblin Chieftain, Greater Demon}
   if ((card=9)or(card=148))and(q in [1,6]) then
    dec(w,10);

   {Elven Hero}
   if card=144 then
   begin
    if q=1 then dec(w,spellpower*2) else if creatures[q-1].cardnum<>0 then inc(w,(aiduel.getattack(pl,q-1)-1)*(spellpower-1)div 2);
    if q=6 then dec(w,spellpower*2) else if creatures[q+1].cardnum<>0 then inc(w,(aiduel.getattack(pl,q+1)-1)*(spellpower-1)div 2);
   end;

   {Dark Phantom, Goblin Pyromancer}
   if ((card=128)or(card=2))and(AIDuel.players[3-pl].creatures[q].cardnum=0) then
    inc(w,20);

   {Harpy}
   if (card=81)and(AIDuel.players[3-pl].creatures[q].cardnum=0) then
   begin
    inc(w,40);
    if creatures[q].abilitywas=false then
     dec(w,20);
   end;

   {Siege Golem}
   if card=142 then
   begin
    if q=1 then dec(w,2) else if creatures[q-1].cardnum=0 then inc(w,6);
    if q=6 then dec(w,2) else if creatures[q+1].cardnum=0 then inc(w,6);
   end;

   {Zealot}
   if card=143 then
   begin
    if q=1 then dec(w,spellpower) else if creatures[q-1].cardnum=0 then inc(w,spellpower);
    if q=6 then dec(w,spellpower) else if creatures[q+1].cardnum=0 then inc(w,spellpower);
   end;

   w:=w*e*3 div 50;

   case gamelogic[thread].playersinfo[AiPlayer].control of
    1:t:=25;
    2:t:=15;
   else
    t:=10;
   end;
   if (pl<>AiPlayer)and(aiduel.players[3-pl].creatures[q].cardnum=0) then w:=w*(100+t) div 100;
   if (pl=AiPlayer)and(aiduel.players[3-pl].creatures[q].cardnum=0) then w:=w*(100-t) div 100;

   if q in [1,6] then dec(w,3);
//   logmessage('   '+cardinfo[card].name+', life='+inttostr(creatures[q].life)+', value='+inttostr(w));

   if (cardinfo[card].special=false) then
   begin
{    if gamelogic[thread].playersinfo[AiPlayer].control=13 then
    begin
     if pl=AiPlayer then
      w:=w*(getpair(card,151)+100)div 100
     else
      w:=w*(getpair(card,152)+100)div 100
    end else if gamelogic[thread].playersinfo[AiPlayer].control=16 then
    begin
     if pl=AiPlayer then
      w:=w*(pairpowerm[card,151]+100)div 100
     else
      w:=w*(pairpowerm[card,152]+100)div 100
    end else}
    if (gamelogic[thread].playersinfo[AiPlayer].control>=5) then
    begin
     if pl=AiPlayer then
      w:=w*(AICreatureGens[card]+100)div 100
     else
      w:=w*(EnemyCreatureGens[card]+100)div 100;
     {$ifdef aitesting}
     if gamelogic[thread].playersinfo[AiPlayer].control>=7 then
     begin
      if pl=AiPlayer then
       gamelogic[thread].playersinfo[AiPlayer].creaturegensused[card]:=1
      else
       gamelogic[thread].playersinfo[AiPlayer].enemycreaturegensused[card]:=1
     end;
     {$endif}
    end;
   end;

   inc(r,w);
  end;

  result:=r;
 end;
end;

function counteff:integer;
begin
 result:=GetEff(AIduel.curplayer)-GetEff(3-AIduel.curplayer);
// logmessage('Counteff result='+inttostr(result)+', cureff='+inttostr(aiduel.cureff));
end;

function firstaction:tAIAction;
begin
 if (lastchecked>0)and(gamelogic[thread].aiunits[lastchecked].FirstAction.ActionType<>0) then
  result:=gamelogic[thread].aiunits[lastchecked].FirstAction
 else
  result:=curaction;
end;

Procedure CalculateAction;
var q,n,w,e,r,t,skipeff,afraid,handdamage,hope,c,card,at1,at2:integer;
    {$ifndef aitesting}
    afraidstr:string;
    {$endif}
begin
// forcelogmessage('tt='+inttostr(aiduel.cureff));
// forcelogmessage('t0='+inttostr(counteff));
 CurAction.ActionResult:=0;
 gamelogic[thread].Aiinfo.lossvalue:=100000000;
 if (aiduel.numaction>15) then
  dec(aiduel.cureff,sqr(aiduel.numaction-15)*2000);
 AIDuel.EndTurn;

 aiduel.curplayer:=3-aiduel.curplayer;
 t:=aiduel.cureff+CountEff;
 inc(CurAction.ActionResult,t);

 if gamelogic[thread].playersinfo[AiPlayer].control=1 then
 begin
//  inc(CurAction.ActionResult,random(500));
 end else
 begin
  // forcelogmessage('t1='+inttostr(CurAction.ActionResult));
  aiduel.curplayer:=3-aiduel.curplayer;

  gamelogic[thread].Aiinfo.lossvalue:=gamelogic[thread].Aiinfo.lossvalue div 2;

  if (checkabilities)and(gamelogic[thread].playersinfo[AiPlayer].control>=3) then
   tmpduel:=aiduel;

  AIDuel.EndTurn;

  {$ifndef aitesting}
  if needstrings then
   afraidstr:='';
  {$endif}

  if (checkabilities)and(abs(aiduel.CurEff)<gamelogic[thread].Aiinfo.lossvalue div 2)and(gamelogic[thread].playersinfo[AiPlayer].control>=3) then
  begin
   skipeff:=counteff+aiduel.cureff;
   afraid:=0;
   aiduel:=tmpduel;

   for q:=1 to 6 do
   if AIduel.CanUseAbility(q) then
   begin
    card:=tmpduel.players[tmpduel.curplayer].creatures[q].cardnum;
    c:=cardinfo[card].abilitycost;
    if c=-1 then c:=0;
    for w:=-6 to 6 do if AIDuel.CanTargetAbility(q,w) then
    begin
     {Gryphon}
     if card=113 then
     begin
      AIDuel.DealDamage(AIDuel.curplayer,0,3-AIDuel.curplayer,0,cardinfo[113].damage,0,false);
      if aiduel.players[aiduel.curplayer].spellpower>=10 then
      begin
       AIDuel.DealDamage(AIDuel.curplayer,0,3-AIDuel.curplayer,0,cardinfo[113].damage,0,false);
       inc(aiduel.cureff,17000);
      end;
     end;
     {Orc Shaman, Elven cavalry}
     if card in [62,66] then
     begin
      {Possible Elven Cavalry attack burst}
      if card=66 then
      for r:=1 to 6 do if aiduel.players[aiduel.curplayer].creatures[r].cardnum in [1,88,132] then
       AIDuel.UseAbility(r,q);
      for e:=2 to aiduel.players[aiduel.curplayer].mana div 3 do
      begin
       inc(aiduel.cureff,6000);
       AIDuel.UseAbility(q,w);
      end;
     end;
     AIDuel.UseAbility(q,w);

     Aiduel.Endturn;
     e:=skipeff-Aiduel.cureff-counteff+650-500*c;
     if cardinfo[tmpduel.players[tmpduel.curplayer].creatures[q].cardnum].dangerousability then
      e:=e * 2;
     if e>afraid then
     begin
      afraid:=e;
      {$ifndef aitesting}
      if needstrings then
       afraidstr:='(afraid '+cardinfo[tmpduel.players[tmpduel.curplayer].creatures[q].cardnum].name+' '+inttostr(afraid)+')';
      {$endif}
     end;
     aiduel:=tmpduel;
    end;
   end;

   aiduel.endturn;
   afraid:=int64(afraid)*45 div 100;
   dec(aiduel.cureff,afraid);
  end;

  t:=aiduel.cureff+CountEff;
  t:=int64(t)*24 div 10;
  inc(CurAction.ActionResult,t);
 // forcelogmessage('t2='+inttostr(CurAction.ActionResult));
  gamelogic[thread].Aiinfo.lossvalue:=gamelogic[thread].Aiinfo.lossvalue div 2;

  if gamelogic[thread].playersinfo[AiPlayer].control>=5 then
  with aiduel do
  begin
   handdamage:=0;
   for q:=1 to players[curplayer].numhandcards do
   case players[curplayer].handcards[q] of
    {Faerie Mage}
    40:Handdamage:=max2(handdamage,players[curplayer].spellpower);
    {Lich}
    53:Handdamage:=max2(handdamage,5);
    {Orc Shaman}
    62:Handdamage:=max2(handdamage,((players[curplayer].spellpower-1)div 3)*3);
   end;
   for w:=1 to 6 do
   begin
    if (players[curplayer].creatures[w].cardnum=0)and(players[3-curplayer].creatures[w].cardnum=0) then
    begin
     for q:=1 to players[curplayer].numhandcards do
     case players[curplayer].handcards[q] of
      {Elven Cavalry}
      66:Handdamage:=max2(handdamage,((players[curplayer].spellpower-3)div 3)*4);
      {Gryphon}
      113:Handdamage:=max2(handdamage,((players[curplayer].spellpower+2)div 5)*5);
      {Sword Mater}
      134:Handdamage:=max2(handdamage,8);
     end;
     break;
    end;
   end;
   if handdamage>=players[3-curplayer].life then
    inc(cureff,100000);
  end;

  with aiduel do
  begin
   at1:=0;
   at2:=0;
   for q:=1 to 6 do
   begin
    if (players[curplayer].creatures[q].cardnum<>0)and(players[3-curplayer].creatures[q].cardnum=0) then
    begin
     e:=getattack(curplayer,q);
     if e>at1 then
     begin
      at2:=at1;
      at1:=e;
     end else
     if e>at2 then
      at2:=e;
    end;
   end;
   inc(players[3-curplayer].life,at1+at2);
   e:=gamelogic[thread].duel.players[3-curplayer].life;   {проверить, сравнить}
   if e<50 then
   begin
    if e<=at2 then at2:=at2*2;
    if e<=at1 then at1:=at1*3 div 2;
    e:=50-e;
    inc(cureff,e*(20+e)*(at1*8+at2*10) div 5)
   end;
  end;

  inc(aiduel.players[3-aiduel.curplayer].life,10);

  AIDuel.EndTurn;
  aiduel.curplayer:=3-aiduel.curplayer;
  t:=aiduel.cureff+CountEff;
  t:=int64(t)*25 div 100;
  inc(CurAction.ActionResult,t);
  // forcelogmessage('t3='+inttostr(CurAction.ActionResult));
 end;

 {$ifndef aitesting}{$ifndef server}
 if (needstrings) then
 begin
  if lastchecked>0 then
   logmessage('Action '+gamelogic[thread].aiunits[lastchecked].AiString+' -> '+s+' result='+inttostr(CurAction.ActionResult)+afraidstr)
  else
   logmessage('Skip result = '+inttostr(CurAction.ActionResult)+afraidstr);
 end;
 {$endif}{$endif}

 if curaction.actionresult>bestaction.ActionResult then
 begin
  bestaction:=FirstAction;
  bestaction.ActionResult:=curaction.actionresult;
 end;
end;

function CountHashe:integer;
var p:pbyte;
    q:integer;
begin
 result:=0;
 p:=@aiduel;
 for q:=1 to sizeof(tduel) do
 begin
  inc(result,q*q*byte(p^));
  inc(p);
 end;
 result:=(result mod AICasheSize)+1;
end;

function AIDuelIsNew(h:integer):boolean;
var q:integer;
begin
 result:=true;
 q:=gamelogic[thread].aicashe[h];
 while q>0 do
 begin
  if CompareMem(@aiduel,@gamelogic[thread].aiunits[q].AIduel,sizeof(tduel)) then
  begin
   result:=false;
   exit;
  end;
  q:=gamelogic[thread].aiunits[q].Previous;
 end;
end;

procedure AddAction;
var q,l,h:integer;
begin
 gamelogic[thread].Aiinfo.lossvalue:=200000000;
// aiDuel.cureff:=0;
 case curaction.actiontype of
  1:begin
     {$ifndef aitesting}
     if needstrings then
     begin
      if aiduel.players[aiduel.curplayer].handcards[curaction.ActionDesc]=0 then
      s:='Use ^unknown card^' else
      s:='Use '+cardinfo[aiduel.players[aiduel.curplayer].handcards[curaction.ActionDesc]].name;
      if curaction.ActionTarget<>0 then
       s:=s+' (target '+inttostr(curaction.ActionTarget)+')';
     end;
     {$endif}

     AIDuel.UseCard(curaction.ActionDesc,curaction.ActionTarget);
    end;
  2:begin
     {$ifndef aitesting}
     if needstrings then
     begin
      if curaction.ActionDesc>0 then
       s:='Ability of '+cardinfo[aiduel.players[aiduel.curplayer].creatures[curaction.ActionDesc].cardnum].name
      else
       s:='Mana Storm';
      if curaction.ActionTarget<>0 then
       s:=s+' (target '+inttostr(curaction.ActionTarget)+')';
     end;
     {$endif}

     AIDuel.UseAbility(curaction.ActionDesc,curaction.ActionTarget);
    end;
  4:begin
     {$ifndef aitesting}
     if needstrings then
      s:='Replace '+cardinfo[aiduel.players[aiduel.curplayer].handcards[curaction.actiondesc]].name;
     {$endif}
     case gamelogic[thread].playersinfo[AiPlayer].control of
      4:if aiduel.dueltypenum=1 then l:=50 else l:=45;
      5:if aiduel.dueltypenum=1 then l:=200 else l:=45;
      else l:=200;
     end;
     h:=GetCardEff(aiduel.curplayer,curaction.actiondesc);
     if (h>l) then
      dec(aiduel.CurEff,10000);
     if h<100 then
      inc(aiduel.CurEff,(100-h)*155);
     inc(aiduel.CurEff,500-aiduel.numaction*2000);
     AIDuel.ReplaceCard(curaction.actiondesc);
    end;
 end;
 if (lastadded<curdiff)and(aiduel.winner=0) then
 begin
  h:=CountHashe;
  if AIDuelIsNew(h) then
  begin
   inc(lastadded);
   gamelogic[thread].aiunits[lastadded].AIduel:=Aiduel;
   {$ifndef aitesting}{$ifndef server}
   if needstrings then gamelogic[thread].aiunits[lastadded].AiString:=gamelogic[thread].aiunits[lastchecked].AiString+' -> '+s;
   {$endif}{$endif}
   gamelogic[thread].aiunits[lastadded].FirstAction:=firstaction;
   gamelogic[thread].aiunits[lastadded].Previous:=gamelogic[thread].aicashe[h];
   gamelogic[thread].aicashe[h]:=lastadded;
  end;
 end;
 CalculateAction;

 aiduel:=gamelogic[thread].aiunits[lastchecked].AIduel;
end;

procedure CheckAIUnit;
var q,w,e,r,t:integer;
begin
 inc(lastchecked);
 aiduel:=gamelogic[thread].aiunits[lastchecked].AIduel;
 with AIduel.players[AIduel.curplayer] do
 begin
  {Sacrifice card}
//  CurAction.ActionType:=3;
//  if gamelogic[thread].playersinfo[AIduel.curplayer].curdeck.decktype<>1 then
//  for q:=1 to numhandcards do if AiDuel.CanSacrificeCard(q) then
//  begin
//   CurAction.ActionDesc:=q;
//   CurAction.ActionTarget:=0;
//   AddAction;
//  end;

  {Use card}
  CurAction.ActionType:=1;
  for q:=numhandcards downto 1 do{ if handcards[q]<>0 then}
  if AIduel.CanUseCard(q) then
  begin
   for w:=-6 to 6 do if AIDuel.CanTargetCard(q,w) then
   begin
    CurAction.ActionDesc:=q;
    CurAction.ActionTarget:=w;
    AddAction;
   end;
  end;

  {Use ability}
  CurAction.ActionType:=2;
  for q:=0 to 6 do if AIduel.CanUseAbility(q) then
  begin
   for w:=-6 to 6 do if AIDuel.CanTargetAbility(q,w) then
   begin
    CurAction.ActionDesc:=q;
    CurAction.ActionTarget:=w;
    AddAction;
   end;
  end;

  {Replace card}
  if (gamelogic[thread].playersinfo[AiPlayer].control>=4)and(AIduel.wasreplace=false)and(gamelogic[thread].duel.numaction=aiduel.numaction)and(gamelogic[thread].playersinfo[AiPlayer].control<>10) then
  for q:=1 to numhandcards do
  if (handcards[q]<>-5)and(handcards[q]<>-1)and(handcards[q]<>149){and(GetCardEff(AIduel.curplayer,q)<=110)} then
  begin
   CurAction.ActionType:=4;
   CurAction.ActionDesc:=q;
   CurAction.ActionTarget:=0;
   AddAction;
  end;
 end;
end;

begin
 aiduel:=gamelogic[thread].duel;
 aiduel.cureff:=0;

 {Card gens preparing}
 case gamelogic[thread].playersinfo[AIduel.curplayer].control of
  -1..4,13:begin
         AIHandGens:=@ZeroGens;
         AICreatureGens:=@ZeroGens;
         EnemyCreatureGens:=@ZeroGens;
        end;
  5,6,12,16,17:begin
        if gamelogic[thread].playersinfo[AIduel.curplayer].Deck.name='#Draft#' then
        begin
{         AIHandGens:=@ZeroGens;
         AICreatureGens:=@ZeroGens;
         EnemyCreatureGens:=@ZeroGens;}
         AIHandGens:=@HandGensDraft;
         AICreatureGens:=@CreatureGensDraft;
         EnemyCreatureGens:=@EnemyCreatureGensDraft;
        end else
        begin
         AIHandGens:=@HandGensCommon;
         AICreatureGens:=@CreatureGensCommon;
         EnemyCreatureGens:=@CreatureGensCommon;
        end;
       end;
  {$ifdef aitesting}
  else begin
         AIHandGens:=@gamelogic[thread].playersinfo[AIduel.curplayer].handgens;
         AICreatureGens:=@gamelogic[thread].playersinfo[AIduel.curplayer].creaturegens;
         EnemyCreatureGens:=@gamelogic[thread].playersinfo[AIduel.curplayer].enemycreaturegens;
       end;
  {$endif}
 end;

// if gamelogic[thread].playersinfo[AIduel.curplayer].control=16 then
//  BuildCrPointsEff(gamelogic[thread].AiInfo.gen1,gamelogic[thread].AiInfo.gen2,gamelogic[thread].AiInfo.gen3,gamelogic[thread].AiInfo.gen4,gamelogic[thread].AiInfo.gen5,gamelogic[thread].AiInfo.gen6);
//  BuildCrPointsEff(68,100,139,171,209,251);

 if evaluationplayer<>0 then
 begin
  gamelogic[thread].AiInfo.AiPlayer:=evaluationplayer;
  AiPlayer:=evaluationplayer;
  action.ActionResult:=GetEff(evaluationplayer)-GetEff(3-evaluationplayer);
 end else
 begin
  lastChecked:=0;
  gamelogic[thread].duel.DrawFactor:=0;
  gamelogic[thread].AiInfo.thinking:=true;
  gamelogic[thread].AiInfo.AiPlayer:=AIduel.curplayer;
  AiPlayer:=AIduel.curplayer;

  {$ifndef aitesting}{$ifndef server}
  if gamelogic[thread].aiinfo.combating=false then
  begin
   logmessage('AI code launched');
   s:='Cards are: ';
   for q:=1 to gamelogic[thread].duel.players[gamelogic[thread].duel.curplayer].numhandcards do
   begin
    w:=gamelogic[thread].duel.players[gamelogic[thread].duel.curplayer].handcards[q];
    if q>1 then
     s:=s+', ';
    s:=s+cardinfo[w].name;
    s:=s+' ('+inttostr(GetCardEff(AIduel.curplayer,q))+')';
   end;
   forcelogmessage(s);
  end;
  {$endif}{$endif}

  case gamelogic[thread].playersinfo[AIplayer].control of
   1:curdiff:=2;
   2:curdiff:=10;
   3:if aiduel.dueltypenum=1 then curdiff:=50 else curdiff:=22;  //50
   4:if aiduel.dueltypenum=1 then curdiff:=500 else curdiff:=28; //500
   else
  {$ifndef aitesting}
   curdiff:=AIMaxWidth;
  {$else}
   if (needdecksgenerating)or(checkabilities) then
    curdiff:=200
   else
    curdiff:=500;
  {$endif}
  end;
  if curdiff<500 then
  for q:=1 to 6 do
  if aiduel.players[aiplayer].creatures[q].cardnum=158 then
   curdiff:=500;
//  curdiff:=AIMaxWidth;
  {$ifdef server}
  if curdiff>maxserverAIwidth then
   curdiff:=maxserverAIwidth;
  {$endif}

  fillchar(gamelogic[thread].AICashe,sizeof(gamelogic[thread].AICashe),0);
  bestaction.ActionResult:=-2000000000;
  needstrings:=(needAiStrings) and (gamelogic[thread].AiInfo.combating=false);

  lastAdded:=1;
  gamelogic[thread].aiunits[lastadded].AIduel:=Aiduel;
  gamelogic[thread].aiunits[lastadded].FirstAction.ActionType:=0;
  gamelogic[thread].aiunits[lastadded].previous:=0;
  CurAction.ActionType:=0;
  CalculateAction;
  aiduel:=gamelogic[thread].duel;

  while (lastchecked<lastadded)and((lastadded<curdiff)or(gamelogic[thread].aiunits[lastchecked+1].AIduel.numaction<gamelogic[thread].aiunits[lastadded].AIduel.numaction)) do
   CheckAiUnit;

  if lastchecked>maxchecked then
   maxchecked:=LastChecked;

  {$ifndef aitesting}
  if (gamelogic[thread].aiinfo.combating=false)and(needAIStrings) then
  begin
   logmessage('lastchecked='+inttostr(lastchecked));
   logmessage('maxchecked='+inttostr(maxchecked));
   forcelogmessage('best result='+inttostr(bestaction.ActionResult));
  end;
  {$endif}

  Action:=bestAction;

  gamelogic[thread].AiInfo.thinking:=false;
 end;
end;

begin
end.
