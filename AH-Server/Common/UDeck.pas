// Author: Alexey Stankevich (Apus Software)
unit UDeck;
interface
uses Cnsts;
const
 _Draft_ = '#Draft#';
 _Classic_ = '#Classic#';
 loadRandomDecks:boolean=true;
// loadRandomDecks:boolean=false;

type

tcards=array[1..512] of smallint;
tshortcardlist=array[1..50] of smallint;
tCampaignDeck=array[1..15] of integer;

tDeck=object
 name:string[127];
 cards:tshortcardlist;
 decktype:integer;                              //outdated
 function ElementsUsed:integer;
 function DeckSize:integer;
 function PresentCards(card:integer):integer;
 function Virtualcard(num:integer):integer;
 function NumDiffCards:integer;
 procedure Clear;
 procedure Prepare;
 procedure Shuffle;
 procedure MutateDeck(numbercopies:integer=3);
 function canAddCard(num,title:integer):boolean;
 function GetMainElement:integer;
 procedure AddCard(num:integer);
 procedure RemoveCard(num:integer);
 procedure GenerateRandom(plnum:integer);
 procedure ImportCampaignDeck(cd:tCampaigndeck);
 function CardsCost(upgraded:string=''):integer;
 procedure SaveToFile(fname:string);
 procedure LoadFromFile(fname:string);
 procedure LoadRandom(plnum:integer);
 procedure SaveAsRandom;
 function RequiredDeckSize:integer;
 function MaximumDeckSize:integer;
end;

tCustomBotDeck=object
 cards:tshortcardlist;
 id:integer;
 control:integer;
 startinglevel:integer;
 botchance:integer;
 procedure LoadFromFile(fname:string);
end;

tCustomBotDecksList=object
 numdecks:integer;
 BotDecks:array[1..128] of tCustomBotDeck;
 procedure init;
 function FindRandomCustomBot(playerhiddenlevel:integer):integer;
 function FindById(id:integer):integer;
 function GetRealLevel(id:integer):integer;
end;

tDeckList=object
 numdecks:integer;
 decknames:array[0..50] of String;
 function AddDeckName(name:string):integer;
 Procedure DeleteDeck(name:string);
 Procedure Load;
 Procedure Save;
end;

threadvar
    deckseed:cardinal;
var
    decklists:array[1..2] of tDeckList; // колоды в локальном режиме: [1] - колоды игрока
    CustomBotDecksList:tCustomBotDecksList;
    curindex,lastindex,nt,nr:integer;

function protectedrandom(max:integer):integer;
procedure preparedeckreport;
procedure TestBotFinder(playerlevel:integer);

implementation
uses sysutils,myservis,Ulogic;

procedure tDeck.MutateDeck;
var q,w,e:integer;
begin
 for q:=1 to 50 do
 if cards[q]>0 then
 begin
  e:=0;
  for w:=1 to q-1 do
  if cards[q]=cards[w] then
   inc(e);
  if ((e=numbercopies-1)and(random(2)=0))or((e=3)and(numbercopies=4)) then
  begin
   e:=cardinfo[cards[q]].element;
   repeat
    w:=random(numcards)+1;
   until (cardinfo[w].element=e)and(cardinfo[w].special=false)and(cardinfo[w].mutationimpossible=false)and(CardInfo[w].basic)and(PresentCards(w)=0);
   cards[q]:=w;
  end;
 end;
end;

function tDeck.GetMainElement:integer;
var a:array[0..4] of integer;
    q,w:integer;
begin
 fillchar(a,sizeof(a),0);
 for q:=1 to 50 do
  inc(a[cardinfo[cards[q]].element]);
 result:=1;
 w:=a[1];
 for q:=2 to 4 do
 if a[q]>w then
 begin
  result:=q;
  w:=a[q];
 end;
end;

function tDeck.canAddCard(num,title:integer):boolean;
var el1,el2,el3,q,w:integer;
    tempdeck:tDeck;
begin
 if (localtesting)and(title<4) then
  title:=4;
 if name='#Draft#' then
  result:=true
 else
 begin
  el1:=0;
  el2:=0;
  el3:=0;
  for q:=1 to 50 do
  begin
   w:=cards[q];
   if w<>0 then
   begin
    if el1=0 then
     el1:=cardinfo[w].element
    else
    if (el1<>cardinfo[w].element)and(el2=0) then
     el2:=cardinfo[w].element
    else
    if (el1<>cardinfo[w].element)and(el2<>cardinfo[w].element) then
     el3:=cardinfo[w].element
   end;
  end;
  if (el1=0)or(el2=0)or(cardinfo[num].element=el1)or(cardinfo[num].element=el2)or(cardinfo[num].element=el3) then
   result:=true
  else
  if (title>=4) and (el3=0) then
   result:=true
  else
  begin
   result:=false;
   if title<=3 then
    errorstring:='{Error}Your deck cannot include cards from more than~two classes (%1 and %2 are already used).%%'+elementnames[el1]+'%%'+elementnames[el2]
   else
    errorstring:='{Error}Your deck cannot include cards from more than three~classes (%1, %2 and %3 are already used).%%'+elementnames[el1]+'%%'+elementnames[el2]+'%%'+elementnames[el3];
  end;
 end;
end;

function tDeck.RequiredDeckSize:integer;
begin
 if name<>'#Draft#' then
  result:=25
 else
  result:=15;
end;

function tDeck.MaximumDeckSize:integer;
begin
 if name<>'#Draft#' then
  result:=30
 else
  result:=20;
end;

procedure tDeck.LoadRandom(plnum:integer);
var f:file of tshortcardlist;
    q:integer;
    c:tshortcardlist;
begin
 if plnum=0 then
  plnum:=random(2)+1;
 if fileexists('inf\rdecks.inf') then
 begin
  assign(f,'inf\rdecks.inf');
  reset(f);
  q:=filesize(f);
  repeat
   curindex:=random(q);
  until (curindex mod 2 <> plnum mod 2)and(curindex<>lastindex);
  seek(f,curindex);
  lastindex:=curindex;
  read(f,c);
  for q:=1 to 50 do
   cards[q]:=c[q];
  close(f);
 end else
 begin
  logmessage('tDeck.LoadRandom: Error in deck loading');
  loadrandomdecks:=false;
  GenerateRandom(1);
 end;
end;

procedure tDeck.SaveAsRandom;
var f:file of tshortcardlist;
    q,fm:integer;
    c:tshortcardlist;
begin
 fm:=filemode;
 filemode:=2;
 assign(f,'inf\rdecks.inf');
 if fileexists('inf\rdecks.inf')=false then
  rewrite(f)
 else
 begin
  reset(f);
  seek(f,filesize(f));
 end;
 for q:=1 to 50 do
  c[q]:=cards[q];
 write(f,c);
 close(f);
 filemode:=fm;
end;

function tDeckList.AddDeckName(name:string):integer;
var q,w:integer;
begin
 for q:=1 to numdecks do
 if uppercase(name)=uppercase(decknames[q]) then
 begin
  decknames[q]:=name;
  result:=q;
  exit;
 end;
 if numdecks<50 then
  inc(numdecks);
 decknames[numdecks]:=name;
 result:=numdecks;
end;

Procedure tDeckList.DeleteDeck(name:string);
var s:string;
    q,w:integer;
begin
 s:='Decks\'+name+'.dck';
 if fileexists(s) then
  deletefile(s);
 for q:=1 to numdecks do
 begin
  if uppercase(decknames[q])=uppercase(name) then
  begin
   for w:=q to numdecks-1 do
    decknames[w]:=decknames[w+1];
   dec(numdecks);
   exit;
  end;
 end;
end;

Procedure tDeckList.Load;
var f:text;
    s:string;
begin
 numdecks:=0;
 s:='Decks\Decklist.txt';
 if fileexists(s) then
 begin
  assign(f,s);
  reset(f);
  while not(eof(f)) do
  begin
   readln(f,s);
   if length(s)>1 then
    AddDeckName(s);
  end;
  close(f);
 end;
end;

Procedure tDeckList.Save;
var f:text;
    q:integer;
begin
 assign(f,'Decks\Decklist.txt');
 rewrite(f);
 for q:=1 to numdecks do
  writeln(f,decknames[q]);
 close(f);
end;

function protectedrandom(max:integer):integer;
begin
// result:=random(max);
 if max=0 then result:=0 else
 begin
  deckseed:=cardinal(1664525)*deckseed+1013904223;
  result:=deckseed mod max;
 end;
{Randseed:=int32(Randseed*$08088405)+1
result:=Randseed*Range shr 32}
end;

procedure tDeck.SaveToFile(fname:string);
var f:text;
    q:integer;
begin
 q:=0;
 assign(f,fname);
 rewrite(f);
 writeln(f,name);
 for q:=1 to 50 do
 if cards[q]<>0 then
  writeln(f,cards[q]);
 close(f);
end;

procedure tDeck.LoadFromFile(fname:string);
var f:text;
    q:integer;
begin
 fillchar(cards,sizeof(cards),0);
 q:=0;
 assign(f,fname);
 reset(f);
 readln(f,name);
 while (not(eof(f)))and(q<50) do
 begin
  inc(q);
  readln(f,cards[q]);
 end;
 close(f);
end;

procedure tCustomBotDeck.LoadFromFile(fname:string);
var f:text;
    q:integer;
    s:string;
begin
 fillchar(cards,sizeof(cards),0);
 q:=0;
 assign(f,fname);
 reset(f);
 readln(f,s);
 while (not(eof(f)))and(q<50) do
 begin
  inc(q);
  readln(f,cards[q]);
 end;
 close(f);
end;

function tDeck.ElementsUsed:integer;
var q,w,e:integer;
    els:array[1..4] of integer;
begin
 result:=0;
 for q:=1 to 4 do els[q]:=0;
 for q:=1 to 50 do if cards[q]<>0 then
 begin
  w:=cardinfo[cards[q]].element;
  if els[w]=0 then
  begin
   els[w]:=1;
   inc(result);
  end;
 end;
end;

function tDeck.DeckSize;
var q:integer;
begin
 result:=0;
 for q:=1 to 50 do if cards[q]<>0 then
  inc(result);
end;

function tDeck.cardsCost(upgraded:string=''):integer;
var q,w:integer;
begin
 result:=0;
 for q:=1 to 50 do if (cards[q]<>0) then
 begin
  w:=cardinfo[cards[q]].mentalcost;
  if (cards[q]>0) and (cards[q]<=length(upgraded))and(upgraded[cards[q]]='*') then
   dec(w,5);
  inc(result,w);
 end;
end;

function tDeck.PresentCards(card:integer):integer;
var q,w:integer;
begin
 result:=0;
 for q:=1 to 50 do
 if cards[q]=card then
  inc(result);
 if card=-1 then
 for q:=1 to 40 do
 if cards[q]=0 then
  inc(result);
end;

function tDeck.Virtualcard(num:integer):integer;
var q,w,e:integer;
begin
 e:=0;
{ if decktype=1 then
 begin
  inc(e);
  if num=1 then
  begin
   result:=-1;
   exit;
  end;
 end;}

 for q:=1 to 50 do
 begin
  inc(e);
  for w:=1 to q-1 do
  if cards[q]=cards[w] then
  begin
   dec(e);
   break;
  end;
  if e=num then
  begin
   result:=cards[q];
   exit;
  end;
 end;
end;

function tDeck.NumDiffCards:integer;
var q,w:integer;
begin
 result:=0;
// if decktype=1 then inc(result);
 for q:=1 to 50 do if cards[q]<>0 then
 begin
  inc(result);
  for w:=1 to q-1 do
  if cards[q]=cards[w] then
  begin
   dec(result);
   break;
  end;
 end;
end;

Procedure tDeck.Clear;
begin
 fillchar(cards,sizeof(cards),0);
end;

Procedure tDeck.Shuffle;
var q,w,e,r,t,n:integer;

procedure deckreport(s:string);
begin
 {$ifndef aitesting}
 logmessage(s);
 logmessage('first card='+inttostr(cards[30]));
 logmessage('median card='+inttostr(cards[15]));
 logmessage('last card='+inttostr(cards[1]));
 logmessage('deckseed='+inttostr(deckseed));
 {$endif}
end;

begin
// deckreport('Deck state before shuffling');
 for q:=1 to 50 do
 for w:=1 to 50 do if cards[w]<>0 then
 begin
  repeat
   n:=protectedrandom(50)+1;
  until cards[n]<>0;
  r:=cards[n];
  cards[n]:=cards[w];
  cards[w]:=r;
 end;
// deckreport('Deck state after shuffling');
end;

const min7:array[40..46] of byte=(2,1,1,1,1,1,1);
      min9:array[40..46] of byte=(2,2,2,2,2,1,1);
      max7:array[40..46] of byte=(4,4,4,4,4,3,3);
      max9:array[40..46] of byte=(5,5,5,4,4,4,3);

procedure tDeck.Prepare;
var q,w:integer;
begin
 {w:=DeckSize+RequiredRituals;
 for q:=1 to w do
 if cards[q]=0 then
  cards[q]:=-1;
 InitialShuffle;}
 Shuffle;
end;

Procedure tDeck.AddCard(num:integer);
var q:integer;
begin
 for q:=1 to 50 do
 if cards[q]=0 then
 begin
  cards[q]:=num;
  exit;
 end;
end;

Procedure tDeck.RemoveCard(num:integer);
var q,w:integer;
begin
 for q:=50 downto 1 do
 if cards[q]=num then
 begin
  for w:=q+1 to 50 do cards[w-1]:=cards[w];
  cards[50]:=0;
  break;
 end;
end;

procedure tDeck.ImportCampaignDeck(cd:tCampaigndeck);
var q,w:integer;
begin
 for q:=1 to 15 do
  cards[q]:=cd[q];
 Shuffle;
 for q:=1 to 15 do
  cards[31-q]:=cd[q];
end;

procedure tDeck.GenerateRandom(plnum:integer);
var q,w,e,r,t,n,s,ss,numSpells,numtotalspells:integer;
    els:array[1..2] of integer;
    opportunities:array[1..numcards*100] of integer;
    cost,startcost,rarity,counter,numdraw1,numkill1,numdraw2,numkill2:integer;
    costs:array[0..10] of integer;

procedure AddCardtotheDeck(card,minpos,maxpos:integer;checklands:boolean=false);
var q,w:integer;
begin
 w:=minpos+random(maxpos-minpos+1);
 if (checklands)and(random(2)=0)and(((w>1)and(cards[w-1]=-1))or(cards[w]=-1)) then
 begin
  AddCardtotheDeck(card,minpos,maxpos,checklands);
  exit;
 end;
 for q:=decksize downto w do
  cards[q+1]:=cards[q];
 cards[w]:=card;
end;

begin
 fillchar(self,sizeof(tdeck),0);
 name:=_Classic_;
 if loadrandomdecks then
 begin
  LoadRandom(plnum);
  exit;
 end;
 repeat
 {$ifdef AITESTING}
  if getcurtime mod 2=0 then
 {$ENDIF}
  protectedrandom(10);
//  inc(nt);
  fillchar(costs,sizeof(costs),0);
  for q:=1 to 50 do cards[q]:=0;
  counter:=0;
  repeat
   n:=0;
   cost:=0;
   startcost:=0;
   rarity:=0;
   numSpells:=0;
   numdraw1:=0;
   numkill1:=0;
   numdraw2:=0;
   numkill2:=0;
   numtotalspells:=0;
   for w:=1 to numcards do
   if cardinfo[w].special=false then
   begin
    r:=cardinfo[w].basicfrequency;
    if needdecksgenerating=false then
     r:=5
    else
     r:=cardinfo[w].basicfrequency;
    for e:=1 to r do
    begin
     inc(n);
     opportunities[n]:=w;
    end;
   end;
   for w:=1 to 30 do
   begin
    r:=24-w;
    if r<0 then r:=0;
    e:=protectedrandom(n)+1;
    cards[w]:=opportunities[e];
    inc(cost,cardinfo[opportunities[e]].cost);
    opportunities[e]:=opportunities[n];
    dec(n);
{    if dtype=1 then
    for q:=1 to 3 do if (w-q>0)and(cards[w]=cards[w-q]) then inc(startcost,1000);}
    if (w>=24) then
    begin
     if cardinfo[cards[w]].life=0 then inc(numSpells);
     if cardinfo[cards[w]].killcard then inc(numkill1);
     if cardinfo[cards[w]].drawcard then inc(numdraw1);
    end;
    if (w>=19) then
    begin
     if cardinfo[cards[w]].killcard then inc(numkill2);
     if cardinfo[cards[w]].drawcard then inc(numdraw2);
    end;
    if w>=21 then inc(startcost,cardinfo[cards[w]].cost);
    if (cardinfo[cards[w]].life=0) then inc(numtotalSpells);
   end;
   for w:=2 to 30 do
   if (cards[w]>0)and(cards[w]=cards[w-1]) then
    numtotalspells:=0;
  until (startcost>=22)and(startcost<=44)and(numspells in [1,2,3])and(numtotalspells>=6);
  s:=0;
  ss:=0;
  for q:=27 to 30 do
  begin
   r:=cards[q];
   if (cardinfo[r].cost>0)and(cardinfo[r].badstart=false) then
   inc(costs[cardinfo[r].cost]);
  end;
 until (costs[1]*costs[2]*costs[3]<>0)and(numkill1>=1)and{(numdraw1>=1)and}(numkill2>=2)and(numdraw2>=1){and(numdraw2>=2)};
// inc(nr);
// logmessage('nt/nr='+inttostr(nt div nr));
end;

procedure tCustomBotDecksList.init;
var q,w:integer;
    s:string;
    loaddecks:boolean;
begin
 fillchar(BotDecks,sizeof(botdecks),0);
 numdecks:=25;
 for q:=1 to numdecks do
 begin
  BotDecks[q].id:=128+q;
  BotDecks[q].botchance:=100;
 end;

 {$ifdef server}
 loaddecks:=true;
 {$else}
 loaddecks:=localtesting;
 {$endif}

 if loaddecks then
 for q:=1 to numdecks do
 begin
  if q>=10 then
   s:=inttostr(q)
  else
   s:='0'+inttostr(q);
  BotDecks[q].LoadFromFile('inf\decks\custom'+s+'.dck');
 end;

 BotDecks[1].startinglevel:=2;     // Чистый порядок
 BotDecks[1].control:=1;

 BotDecks[2].startinglevel:=2;     // Смерть и немного хаоса
 BotDecks[2].botchance:=50;
 BotDecks[2].control:=1;

 BotDecks[3].startinglevel:=1;     // Порядок и жизнь
 BotDecks[3].control:=1;

 BotDecks[4].startinglevel:=1;     // Порядок и смерть
 BotDecks[4].control:=1;

 BotDecks[5].startinglevel:=3;    // Жизнь и смерть
 BotDecks[5].control:=2;

 BotDecks[6].startinglevel:=5;    // Хаос и жизнь, отстрел
 BotDecks[6].control:=2;

 BotDecks[7].startinglevel:=4;    // Порядок и жизнь, полуконтроль
 BotDecks[7].control:=2;

 BotDecks[8].startinglevel:=6;    // Хаос и смерть, библиотекари
 BotDecks[8].control:=2;

 BotDecks[9].startinglevel:=9;
 BotDecks[9].control:=3;
 BotDecks[9].botchance:=75;

 BotDecks[10].startinglevel:=13;
 BotDecks[10].control:=4;
 BotDecks[10].botchance:=80;

 BotDecks[11].startinglevel:=8;
 BotDecks[11].control:=3;

 BotDecks[12].startinglevel:=10;
 BotDecks[12].control:=3;

 BotDecks[13].startinglevel:=20;
 BotDecks[13].control:=5;
 BotDecks[13].botchance:=120;

 BotDecks[14].startinglevel:=16;
 BotDecks[14].control:=4;

 BotDecks[15].startinglevel:=22;
 BotDecks[15].control:=5;
 BotDecks[15].botchance:=120;

 BotDecks[16].startinglevel:=15;
 BotDecks[16].control:=4;

 BotDecks[17].startinglevel:=7;
 BotDecks[17].control:=3;

 BotDecks[18].startinglevel:=11;
 BotDecks[18].control:=4;

 BotDecks[19].startinglevel:=12;
 BotDecks[19].control:=4;
 BotDecks[19].botchance:=75;

 BotDecks[20].startinglevel:=18;
 BotDecks[20].control:=5;
 BotDecks[20].botchance:=40;

 BotDecks[21].startinglevel:=14;
 BotDecks[21].control:=4;
 BotDecks[21].botchance:=60;

 BotDecks[22].startinglevel:=1;
 BotDecks[22].control:=1;
 BotDecks[22].botchance:=60;

 BotDecks[23].startinglevel:=2;
 BotDecks[23].control:=1;

 BotDecks[24].startinglevel:=3;
 BotDecks[24].control:=2;
 BotDecks[24].botchance:=80;

 BotDecks[25].startinglevel:=4;
 BotDecks[25].control:=2;
 BotDecks[25].botchance:=80;
end;

function tCustomBotDecksList.FindRandomCustomBot(playerhiddenlevel:integer):integer;
var best5:array[0..20,1..3] of integer;
    q,w,e,r,t,checkdecks,check:integer;
begin
 if playerhiddenlevel>0 then
  checkdecks:=(18+playerhiddenlevel) div 3
 else
  checkdecks:=3;
 if checkdecks>12 then
  checkdecks:=12;
 if playerhiddenlevel>22 then
  dec(checkdecks);
 if playerhiddenlevel>7 then
  dec(playerhiddenlevel);
 playerhiddenlevel:=playerhiddenlevel*10-1;
 case playerhiddenlevel of
  30:dec(playerhiddenlevel,5);
  40:dec(playerhiddenlevel,1);
 end;
 for q:=1 to checkdecks do
 begin
  best5[q,1]:=0;
  best5[q,2]:=9999;
  best5[q,3]:=0;
 end;
 for q:=1 to numdecks do
 begin
  check:=checkdecks+1;
  best5[check,1]:=q;
  best5[check,2]:=abs(playerhiddenlevel-GetRealLevel(botdecks[q].id)*10)+random(4);
  best5[check,3]:=botdecks[q].botchance;
  while (check>1)and((best5[check,2]<best5[check-1,2])or((best5[check,2]=best5[check-1,2])and(random(2)=0))) do
  begin
   best5[0]:=best5[check];
   best5[check]:=best5[check-1];
   best5[check-1]:=best5[0];
   dec(check);
  end;
 end;
 check:=0;
 for q:=1 to checkdecks do
 if best5[q,1]<>0 then
  inc(check,(checkdecks+1-q)*best5[q,3]);
 w:=random(check);
 for q:=1 to checkdecks do
 begin
   dec(w,(checkdecks+1-q)*best5[q,3]);
  if w<=0 then break;
 end;
 result:=best5[q,1];
end;

function tCustomBotDecksList.FindById(id:integer):integer;
var q:integer;
begin
 for q:=1 to numdecks do
 if BotDecks[q].id=id then
 begin
  result:=q;
  exit;
 end;
end;

function tCustomBotDecksList.GetRealLevel(id:integer):integer;
var q:integer;
begin
 {$ifdef server}
 // потом Кулеру заменить на что-то более адекватное
 q:=FindById(id);
 result:=BotDecks[q].startinglevel;
 {$else}
 q:=FindById(id);
 result:=BotDecks[q].startinglevel;
 {$endif}
end;

procedure TestBotFinder(playerlevel:integer);
var botlevels:array[0..50] of integer;
    q,w:integer;
begin
 if CustomBotDecksList.numdecks=0 then
  CustomBotDecksList.init;

 fillchar(botlevels,sizeof(botlevels),0);
 forcelogmessage('------ Testing bot finder for level '+inttostr(playerlevel));
 for q:=1 to 100000 do
 begin
  w:=CustomBotDecksList.FindRandomCustomBot(playerlevel);
  inc(botlevels[CustomBotDecksList.botdecks[w].startinglevel]);
 end;
 for q:=0 to 50 do
 if botlevels[q]>0 then
  forcelogmessage('Bot level '+inttostr(q)+': '+inttostr(botlevels[q]));
 forcelogmessage('---');
end;

procedure preparedeckreport;
var di:array[0..numcards,1..2] of integer;
    q,w,e,r,t:integer;
    f:file of tshortcardlist;
    c:tshortcardlist;
    s:string;
begin
 if fileexists('inf\rdecks.inf') then
 begin
  for q:=1 to numcards do
  begin
   di[q,1]:=q;
   di[q,2]:=0;
  end;
  assign(f,'inf\rdecks.inf');
  reset(f);
  while not(eof(f)) do
  begin
   read(f,c);
   for q:=1 to 30 do
   begin
    if q<12 then
     w:=1
    else
    if q<20 then
     w:=q-10
    else
     w:=10;
    inc(di[c[q],2],w);
   end;
  end;
  close(f);
  for q:=2 to numcards do
  for w:=2 to numcards do if di[w,2]>di[w-1,2] then
  begin
   di[0,1]:=di[w,1];
   di[w,1]:=di[w-1,1];
   di[w-1,1]:=di[0,1];
   di[0,2]:=di[w,2];
   di[w,2]:=di[w-1,2];
   di[w-1,2]:=di[0,2];
  end;
  forcelogmessage('Deck analizing report:');
  for q:=1 to numcards do
  begin
   w:=di[q,1];
   s:=cardinfo[w].name;
   while length(s)<23 do
    s:=s+' ';
   s:=s+inttostr(di[q,2]);
   while length(s)<30 do
    s:=s+' ';
   s:=s+inttostr(cardinfo[w].basicfrequency);
   forcelogmessage(s);
  end;
 end;
end;

begin
 randomize;
 deckseed:=cardinal(randseed);
// nt:=0;
// nr:=0;
end.
