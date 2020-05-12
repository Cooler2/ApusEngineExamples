// Author: Alexey Stankevich (Apus Software)
unit UDraftLogic;
{$R+}
interface
uses Cnsts,UOutput,ULogic,UDeck,UCardGens;

type

PDraftPlayer=^TDraftPlayer;
tDraftPlayer=object
 Name:string[64];
 control:integer;
 deck:tdeck;
 cards,availablecards:tshortcardlist;
 wins:integer;
 time:integer;      // время в секундах, потраченное игроком в драфте (на выбор карт, составление деки, ходы)
 cardTaken:boolean; // игрок уже потянул карту на текущем этапе
 deckBuilt:boolean; // колода составлена
 played:TDateTime; // когда закончил бой в текущем раунде
 place:integer;  // итоговое место

 draftgens:tcardgens;
 draftgensUsed:tcardgens;
 draftpairs,draftpairsused:tpairgens;

 procedure CreateAIDeck;
 function TakeCard(card:integer):boolean; // card=0 - take random available card
 function DeckMade(d:tshortcardlist):integer; // 0 - OK, либо номер недоступной карты
end;

tDraftGeneralInfo=object
 InitialTime:int64;
 Players:array[1..4] of tDraftPlayer;
 opponents:array[1..3,1..4] of integer; // [round, player] - кому с кем играть (индекс игрока)
 history:array[1..13] of string [63];
 ts:array[1..15] of string [15];
 historysize:integer;
 round:integer;
 procedure PrepareNextRound; // Заполняет турнирную таблицу для следующего раунда
 function GetAIChoose(numplayer:integer):integer;   // result in 1-25
 procedure Init;
 procedure MakeAIChoices(maxTime:integer=10); // тянет карту для всех ботов и сдвигает наборы карт по кругу
 procedure AddHistory(s:string);
 procedure ReportWinner(name:string);
end;

function numdrcards(cards:tshortcardlist):integer;

implementation
uses myservis,sysutils,ucompai,NetCommon;

// Кол-во выбранных карт
function numdrcards(cards:tshortcardlist):integer;
var q:integer;
begin
 result:=0;
 for q:=1 to numdraftcards do
 if cards[q]>0 then
  result:=q;
end;

procedure tDraftGeneralInfo.Init;
var q,w,e,r,t,tt,qq,card:integer;
begin
 fillchar(self,sizeof(tDraftGeneralInfo),0);
 initialtime:=MyTickCount;
 historysize:=0;
 round:=0;
 players[1].control:=0;
 players[1].name:='Player';
 for q:=2 to 4 do
 begin
  players[q].control:=q+2{5};
  players[q].name:=ainames[players[q].control]{+inttostr(q-1)};
 end;

 for q:=1 to 4 do
 begin
  for w:=1 to numdraftcards do
  begin
   repeat
    repeat
     card:=random(numcards)+1;
    until (random(10)<cardinfo[card].draftfrequency)and(cardinfo[card].special=false);
    for r:=1 to w-1 do
    if players[q].availablecards[r]=card then
     card:=0;
    if (card>0)and(q=4) then
    begin
     t:=0;
     for e:=1 to q-1 do
     for r:=1 to numdraftcards do
     if players[q].availablecards[w]=card then
      inc(t);
     if t=3 then
      card:=0;
    end;
   until card<>0;
   players[q].availablecards[w]:=card;
   players[q].cards[w]:=0;
  end;

  for w:=1 to numdraftcards-1 do
  for e:=1 to numdraftcards-1 do
  if cardinfo[players[q].availablecards[e]].element>cardinfo[players[q].availablecards[e+1]].element then
  begin
   r:=players[q].availablecards[e];
   players[q].availablecards[e]:=players[q].availablecards[e+1];
   players[q].availablecards[e+1]:=r;
  end;
 end;
 AddHistory('Draft tournament started');
end;

procedure tDraftGeneralInfo.AddHistory(s:string);
var q,w:integer;
    s2,s3:string;
begin
 if historysize<13 then
  inc(historysize)
 else
 for q:=1 to 12 do
  history[q]:=history[q+1];

 history[historysize]:=s;
 q:=(MyTickCount-initialTime) div 1000;
 w:=q div 3600;
 q:=q mod 3600;

 s2:=inttostr(q div 60);
 s3:=inttostr(q mod 60);

 if (w>0)and(length(s2)<2) then
  s2:='0'+s2;

 if length(s3)<2 then
  s3:='0'+s3;

 ts[historysize]:=s2+':'+s3;
 if w>0 then
  ts[historysize]:=inttostr(w)+':'+ts[historysize];
end;

procedure tDraftGeneralInfo.ReportWinner(name:string);
var q:integer;
begin
 name:=uppercase(name);
 for q:=1 to 4 do
 if uppercase(players[q].Name)=name then
  inc(players[q].wins);
end;

function tDraftGeneralInfo.GetAIChoose(numplayer:integer):integer;
var q,w,e,r,t,numAIcards,numAvailablecards:integer;
    tmpcards:tshortcardlist;

function cardspower:integer;
var costs:array[0..5] of integer;
    q,w,e,r,t:integer;
    kp,dp:integer;
    bst:array[1..4] of integer;
    tm:array[0..20] of integer;
begin
 result:=0;
 fillchar(costs,sizeof(costs),0);
 for q:=1 to numaicards do
 begin
  fillchar(tm,sizeof(tm),0);
  for w:=1 to numaicards do{ if w<>q then}
  {$ifndef server}
  if players[numplayer].control=12 then
  begin
   if q<>w then
   begin
    tm[w]:=players[numplayer].draftpairs[tmpcards[q],tmpcards[w]];
    players[numplayer].draftpairsused[tmpcards[q],tmpcards[w]]:=1;
   end else
   begin
    tm[w]:=players[numplayer].draftpairs[tmpcards[q],150];
    players[numplayer].draftpairsused[tmpcards[q],150]:=1;
   end;
  end else
  {$endif}
  if players[numplayer].control=16 then
  begin
   if q<>w then
    tm[w]:=draftpowerpl[tmpcards[q],tmpcards[w]]
   else
    tm[w]:=draftpowerpl[tmpcards[q],150]
  end
  else
  begin
   if q<>w then
    tm[w]:=draftpower[tmpcards[q],tmpcards[w]]
   else
    tm[w]:=draftpower[tmpcards[q],150]
  end;
  for e:=2 to numaicards do
  for r:=2 to numaicards do if tm[r]>tm[r-1] then
  begin
   tm[0]:=tm[r];
   tm[r]:=tm[r-1];
   tm[r-1]:=tm[0];
  end;
  r:=0;
  for e:=1 to draftc-1 do
   inc(r,tm[e]*(draftc-e));
  inc(result,r div draftc);
 end;

 for q:=1 to numAICards do
 begin
  w:=cardinfo[tmpcards[q]].cost;
  if w>5 then
   w:=5;
  inc(costs[w]);
 end;
 if costs[2]>5 then
  dec(result,(costs[2]-5)*20);
 for q:=3 to 5 do
 if costs[q]>4 then
  dec(result,(costs[q]-4)*55);
 kp:=0;
 dp:=0;
 for q:=1 to numaicards do
 begin
  inc(kp,cardinfo[tmpcards[q]].killAIeffect);
  inc(kp,cardinfo[tmpcards[q]].drawAIeffect);
 end;
 if kp>25 then
  kp:=25;
 if dp>25 then
  dp:=25;
 inc(result,trunc(sqrt(kp)*8));
 inc(result,trunc(sqrt(dp)*20));

 //Reducing AI quality
 if players[numplayer].control<6 then
 begin
  case players[numplayer].control of
{   2:w:=85;
   3:w:=30;
   4:w:=16;//w:=6;
   5:w:=5;}
   2:w:=200;
   3:w:=50;
   4:w:=25;
   5:w:=8;
  end;
  inc(result,random((numDraftCards-numaicards)*w));
  if (numaicards<=6)and(cardinfo[tmpcards[numaicards]].life=0) then
   dec(result,random(20));
 end;

 if (players[numplayer].control>=5)and(numaicards<8) then
 begin
  for w:=1 to 3 do
   bst[w]:=0;
  for w:=1 to numAvailablecards do if tmpcards[numAIcards]<>players[numplayer].availablecards[w] then
  begin
   {$ifndef server}
   if players[numplayer].control=12 then
   begin
    tm[w]:=players[numplayer].draftpairs[tmpcards[numAIcards],players[numplayer].availablecards[w]];
    players[numplayer].draftpairsused[tmpcards[numAIcards],players[numplayer].availablecards[w]]:=1;
   end else
   {$endif}
   if players[numplayer].control=16 then
    bst[4]:=draftpowerpl[tmpcards[numAIcards],players[numplayer].availablecards[w]]
   else
    bst[4]:=draftpower[tmpcards[numAIcards],players[numplayer].availablecards[w]];
   e:=4;
   while (e>1)and(bst[e]>bst[e-1]) do
   begin
    r:=bst[e];
    bst[e]:=bst[e-1];
    bst[e-1]:=r;
    dec(e);
   end;
  end;
  r:=(bst[1]*3+bst[2]*2+bst[3]) div 3;
  if players[numplayer].control in [7..15] then
   r:=r*(50+players[numplayer].draftgens[tmpcards[numAIcards]]) div 50
  else
  inc(result,r div 2);
 end;
end;


begin
 numAvailablecards:=numdrcards(players[numplayer].availablecards);
 numAIcards:=numdrcards(players[numplayer].cards)+1;
 if players[numplayer].control<2 then
 begin
  result:=random(numAvailablecards)+1;
 end else
 begin
  t:=-99999999;
  tmpcards:=players[numplayer].cards;
  for q:=1 to numAvailablecards do
  begin
   tmpcards[numAIcards]:=players[numplayer].availablecards[q];
   r:=cardspower;
   if r>t then
   begin
    t:=r;
    result:=q;
   end;
  end;
 end;
end;

procedure tDraftPlayer.CreateAIDeck;
var q,qq,w,ww,ww2,e,ee,r,t,tt,c:integer;
    tmpdeck:tdeck;
    tmpcards:tshortcardlist;
    cardind:tshortcardlist;
    cardstats:array[1..50,1..2] of integer;

function deckpower:integer;
var costs:array[0..5] of integer;
    q,w,e,r,t:integer;
    kp,dp:integer;
    tm:array[0..20] of integer;
begin
 result:=0;
 for q:=1 to 15 do
 begin
  fillchar(tm,sizeof(tm),0);
  for w:=1 to 15 do{ if w<>q then}
  {$ifndef server}
  if control=12 then
  begin
   if q<>w then
   begin
    tm[w]:=draftpairs[tmpdeck.cards[q],tmpdeck.cards[w]];
    draftpairsused[tmpdeck.cards[q],tmpdeck.cards[w]]:=1;
   end else
   begin
    tm[w]:=draftpairs[tmpdeck.cards[q],150];
    draftpairsused[tmpdeck.cards[q],150]:=1;
   end;
  end else
  {$endif}
  if control=16 then
  begin
   if q<>w then
    tm[w]:=draftpowerpl[tmpdeck.cards[q],tmpdeck.cards[w]]
   else
    tm[w]:=draftpowerpl[tmpdeck.cards[q],150]
  end
  else
  begin
   if q<>w then
    tm[w]:=draftpower[tmpdeck.cards[q],tmpdeck.cards[w]]
   else
    tm[w]:=draftpower[tmpdeck.cards[q],150]
  end;
  for e:=1 to 15 do
  for r:=2 to 15 do if tm[r]>tm[r-1] then
  begin
   tm[0]:=tm[r];
   tm[r]:=tm[r-1];
   tm[r-1]:=tm[0];
  end;
  r:=0;
  for e:=1 to draftc-1 do
   inc(r,tm[e]*(draftc-e));

  inc(result,r div draftc);
 end;

 fillchar(costs,sizeof(costs),0);
 for q:=1 to 15 do
 begin
  w:=cardinfo[tmpdeck.cards[q]].cost;
  if w>5 then
   w:=5;
  inc(costs[w]);
 end;
 for q:=1 to 3 do
 if costs[q]=0 then
  dec(result,35);

 if costs[2]>5 then
  dec(result,(costs[2]-5)*20);
 for q:=3 to 5 do
 if costs[q]>4 then
  dec(result,(costs[q]-4)*55);
 kp:=0;
 dp:=0;
 for q:=1 to 15 do
 begin
  inc(kp,cardinfo[tmpdeck.cards[q]].killAIeffect);
  inc(kp,cardinfo[tmpdeck.cards[q]].drawAIeffect);
 end;
 if kp>25 then
  kp:=25;
 if dp>25 then
  dp:=25;
 inc(result,trunc(sqrt(kp)*8));
 inc(result,trunc(sqrt(dp)*20));
end;

begin
 deck.name:='#Draft#';
 deck.decktype:=1;
 inc(time,random(50));
 if false{control<2} then
 begin
  for q:=1 to 15 do
  begin
   w:=numdrcards(cards);
   r:=random(w)+1;
   deck.cards[q]:=cards[r];
   cards[r]:=cards[w];
   cards[w]:=0;
  end;
 end else
 begin
  t:=-99999999;
  fillchar(tmpdeck.cards,sizeof(tmpdeck.cards),0);
  for q:=1 to 15 do
   tmpdeck.cards[q]:=cards[q];
  t:=deckpower;
  deck.cards:=tmpdeck.cards;

  fillchar(cardstats,sizeof(cardstats),0);
  case control of
   1,2:c:=10;
   3:c:=20;
   4:c:=40;
   else c:=200;
  end;
  for q:=1 to c do
  begin
   tmpcards:=cards;
   for w:=1 to numdraftcards do
    cardind[w]:=w;
   fillchar(tmpdeck.cards,sizeof(tmpdeck.cards),0);
   for w:=1 to 15 do
   begin
    e:=random(numdraftcards+1-w)+1;
    tmpdeck.cards[w]:=tmpcards[e];
    tmpcards[e]:=tmpcards[numdraftcards+1-w];
    tmpcards[numdraftcards+1-w]:=0;
    r:=cardind[e];
    cardind[e]:=cardind[numdraftcards+1-w];
    cardind[numdraftcards+1-w]:=r;
   end;
   r:=deckpower;
   if r>t then
   begin
    t:=r;
    deck.cards:=tmpdeck.cards;
   end;
   for w:=1 to 15 do
   begin
    e:=cardind[numdraftcards+1-w];
    inc(cardstats[e,1],r);
    inc(cardstats[e,2],1);
   end;
  end;
  for q:=1 to numdraftcards do
  if cardstats[q,2]>0 then
   cardstats[q,1]:=cardstats[q,1] div cardstats[q,2]
  else
   cardstats[q,1]:=-9999;
  for q:=numdraftcards downto 16 do
  begin
   e:=999999999;
   ee:=0;
   for w:=1 to q do
   if cardstats[w,1]<e then
   begin
    e:=cardstats[w,1];
    ee:=w;
   end;
   cardstats[ee,1]:=cardstats[q,1];
   r:=cards[ee];
   cards[ee]:=cards[q];
   cards[q]:=r;
  end;
  for w:=3 to 16 do
  for ww:=w+1 to 17 do
  for ww2:=ww+1 to 18 do
  begin
   qq:=0;
   for q:=1 to 18 do
   if (q<>w)and(q<>ww)and(q<>ww2) then
   begin
    inc(qq);
    tmpdeck.cards[qq]:=cards[q];
   end;
   r:=deckpower;
   if r>t then
   begin
    t:=r;
    deck.cards:=tmpdeck.cards;
   end;
  end;
 end;
end;

function tDraftPlayer.TakeCard(card:integer):boolean;
var
 q,numcard,n:integer;
begin
 result:=false;
 if card=0 then begin
  n:=0;
  for q:=1 to numdraftcards do
   if availableCards[q]<>0 then n:=q
    else break;
  if n>0 then begin
   numCard:=1+random(n);
   card:=availableCards[1+random(n)];
  end;
 end;
 numCard:=-1;
 for q:=1 to numdraftcards do
  if availableCards[q]=card then numCard:=q;
 if numCard<0 then exit;

 q:=numdrcards(cards);
 cards[q+1]:=card;
 for q:=numcard to numdraftcards-1 do
  availablecards[q]:=availablecards[q+1];
 availablecards[numDraftCards]:=0;

 cardTaken:=true;
 result:=true;
end;

function TDraftPlayer.DeckMade(d:tshortcardlist):integer;
var
 i,j,card:integer;
 fl:boolean;
begin
 result:=0;
 // Проверить что нет левых карт
 for i:=1 to high(d) do begin
  card:=d[i];
  if card<>0 then begin
   fl:=false;
   for j:=1 to high(cards) do
    if cards[j]=card then fl:=true;
   if not fl then begin
    result:=card; exit;
   end;
  end;
 end;
 deck.cards:=d;
 deckBuilt:=true;
end;


{procedure tDraftGeneralInfo.GiveCardToPlayer(numplayer,numcard:integer);
var q,w,n,el:integer;
begin
 q:=numdrcards(players[numplayer].cards);
 players[numplayer].cards[q+1]:=players[numplayer].availablecards[numcard];
 for q:=numcard to numdraftcards-1 do
  players[numplayer].availablecards[q]:=players[numplayer].availablecards[q+1];
 players[numplayer].availablecards[numDraftCards]:=0;
end;}

procedure tDraftGeneralInfo.MakeAIChoices(maxTime:integer=10);
var q,w,e:integer;
    temp:tshortcardlist;
begin
 for q:=1 to 4 do
 if players[q].control<>0 then
 begin
  w:=GetAIChoose(q);
  players[q].TakeCard(players[q].availablecards[w]);
  inc(players[q].time,random(w*2));
//  GiveCardToPlayer(q,w);
 end;
 temp:=players[1].availablecards;
 players[1].availablecards:=players[2].availablecards;
 players[2].availablecards:=players[3].availablecards;
 players[3].availablecards:=players[4].availablecards;
 players[4].availablecards:=temp;
end;

procedure tDraftGeneralInfo.PrepareNextRound;
var q,w,e:integer;
begin
 inc(round);
 for q:=1 to 3 do
 if opponents[round,q]=0 then
 begin
  repeat
   e:=random(4)+1;
   if opponents[round,e]>0 then
    e:=0
   else
   if e=q then
    e:=0
   else
   for w:=1 to round do
   if opponents[w,q]=e then
    e:=0;
  until e<>0;
  opponents[round,q]:=e;
  opponents[round,e]:=q;
 end;
 for q:=1 to 4 do
  players[q].played:=0;
end;

end.
