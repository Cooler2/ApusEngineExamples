unit NetCommon;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

type
 TReplayPlayerInfo=packed record
  name:string[31];
  life:smallint;
  spellpower,mana:smallint;
  level:smallint;
  numdeckcards,numhandcards:shortint;
  handcards:array[1..8] of smallint;
  faceNum:integer;
 end;

// Возвращает текст объяснения либо пустую строку
function IsValidLogin(login:widestring):string;
function IsValidPassword(pwd:widestring):string;
function IsValidName(wname:WideString;allowSpaces:boolean=false):string;

// Преобразует колоду из строкового формата БД (utf8: каждый символ - номер карты) в массив номеров карт
procedure StrToDeck(st:string;var cards:array of smallint);
// Преобразует колоду в строковый формат БД (utf8: каждый символ - номер карты)
function DeckToStr(cards:array of smallint):string;

procedure CopyDeck(var sour,dest:array of smallint);
// cards - список номеров карт (колода)
// если upgraded[i]='*' - значит карта i-го типа заапгрейджена и стоит на 5 меньше
function CalculateDeckCost(cards:array of smallint;upgraded:string=''):integer;
function DeckToText(deck:array of smallint):string;
function DescribeDeck(cards:array of smallint;useNumbers:boolean=false):string;
function CardsCount(st:string):integer; // st - строка из цифр, обозначающих кол-во кар i-го типа

function EncryptSequence(index:integer;pwd:string):integer;

implementation
 uses SysUtils,MyServis,Cnsts;

function EncryptSequence(index:integer;pwd:string):integer;
var
 idx:integer;
begin
 idx:=1+index mod length(pwd);
 result:=byte(pwd[idx])+(index*index mod 7);
end;

function CardsCount(st:string):integer;
var
 ch:char;
begin
 result:=0;
 for ch in st do begin
  if ch in ['1'..'6'] then inc(result,ord(ch)-$30);
  if ch='*' then inc(result,3);
 end;
end;

function DeckToText(deck:array of smallint):string;
 var
  i:integer;
 begin
  result:='';
  for i:=low(deck) to high(deck) do begin
   if deck[i]=0 then continue;
   if i>low(deck) then result:=result+',';
   result:=result+inttostr(deck[i]);
  end;
 end;

function CalculateDeckCost(cards:array of smallint;upgraded:string=''):integer;
 var
  i,c:integer;
 begin
  result:=0;
  for i:=low(cards) to high(cards) do
   if (cards[i]<>0) and
      (cards[i]>=low(cardinfo)) and
      (cards[i]<=high(cardinfo)) then begin
    c:=cardinfo[cards[i]].mentalCost;
    if (cards[i]>0) and (cards[i]<=length(upgraded)) then
     if upgraded[cards[i]]='*' then c:=c-5;
    if c<0 then c:=0;
    inc(result,c);
   end;
 end;

procedure CopyDeck(var sour,dest:array of smallint);
 var
  i,j:integer;
 begin
  j:=low(sour);
  for i:=low(dest) to high(dest) do begin
   if j<=high(sour) then dest[i]:=sour[j]
    else dest[i]:=0;
   inc(j);
  end;
 end;

procedure StrToDeck(st:string;var cards:array of smallint);
 var
  i,p:integer;
  wst:WideString;
 begin
  for i:=low(cards) to high(cards) do cards[i]:=0;
  wst:=DecodeUTF8(st);
  p:=low(cards);
  for i:=1 to length(wst) do begin
   if p>high(cards) then break;
   cards[p]:=smallint(wst[i])-39;
   inc(p);
  end;
 end;

function DeckToStr(cards:array of smallint):string;
 var
  i,p,size:integer;
  wst:WideString;
 begin
  size:=high(cards)-low(cards)+1;
  for i:=high(cards) downto low(cards) do begin
   if cards[i]<>0 then break;
   dec(size);
  end;
  SetLength(wst,size);
  p:=low(cards);
  for i:=1 to size do begin
   wst[i]:=WideChar(cards[p]+39);
   inc(p);
  end;
  result:=EncodeUTF8(wst);
 end;

function DescribeDeck(cards:array of smallint;useNumbers:boolean=false):string;
 var
  i,n:integer;
  a:array[mincard..numcards] of byte;
 begin
  result:='';
  for i:=low(a) to high(a) do a[i]:=0;
  for i:=low(cards) to high(cards) do
   if cards[i]<>0 then inc(a[cards[i]]);

  for n:=3 downto 1 do
   for i:=low(a) to high(a) do
    if a[i]=n then begin
     if useNumbers then begin
      if result<>'' then result:=result+',';
      result:=result+inttostr(n)+'x'+inttostr(i);
     end else begin
      if result<>'' then result:=result+#13#10;
      result:=result+inttostr(n)+' x '+cardInfo[i].name;
     end;
    end;
 end;

function IsValidLogin(login:widestring):string;
var
 i:integer;
begin
 result:='';
 if login='' then begin
  result:='^Email cannot be empty!^';
  exit;
 end;
 if length(login)>60 then begin
  result:='^This email is too long!^';
  exit;
 end;
 for i:=1 to length(login) do
  if not (login[i] in ['A'..'Z','a'..'z','0'..'9','_','-','.','@']) then begin
   result:='^Unallowed character:^ "'+EncodeUTF8(login[i])+'"';
   exit;
  end;
 if (pos('@',login)=0) or (pos('.',login)=0) or (length(login)<9) then begin
  result:='^This is not a valid email^';
  exit;
 end;
end;

function IsValidPassword(pwd:widestring):string;
var
 i:integer;
 chars:string;
 min,max:byte;
begin
 if pwd='' then begin
  result:='^Password cannot be empty!^';
  exit;
 end;
 if length(pwd)<6 then begin
  result:='^Password is too short!^';
  exit;
 end;
 if length(pwd)>40 then begin
  result:='^Password is too long!^';
  exit;
 end;
 for i:=1 to length(pwd) do
  if not (pwd[i] in [#32..#126]) then begin
   result:='^Unallowed character:^ '+EncodeUTF8(pwd[i]);
   exit;
  end;
 chars:=''; min:=255; max:=0;
 for i:=1 to length(pwd) do begin
  if pos(pwd[i],chars)=0 then chars:=chars+pwd[i];
  min:=min2(min,ord(pwd[i]));
  max:=max2(max,ord(pwd[i]));
 end;
 if (length(chars)<4) or (max-min<8) then begin
  result:='^Password is too simple!^';
  exit;
 end;
end;

function IsValidName(wname:WideString;allowSpaces:boolean=false):string;
var
 i,cnt1,cnt2:integer;
begin
 result:='';
// wName:=DecodeUTF8(name);
 if length(wname)<4 then begin
  result:='^Name is too short!^';
  exit;
 end;
 if length(wname)>20 then begin
  result:='^Name is too long!^';
  exit;
 end;
 for i:=1 to length(wname) do
  if not (wname[i] in ['A'..'Z','a'..'z','0'..'9','&','_','-','.','(',')','[',']','<','>']) then begin
   if allowSpaces and (wname[i]=' ') and (i>1) and (i<length(wname)) and (wname[i]<>wname[i-1]) then continue;
   if allowSpaces and (wname[i]='!') and (i=length(wname)) then continue;
   result:='^Unallowed character:^ "'+EncodeUTF8(wname[i])+'"';
   exit;
  end;

 cnt1:=0; cnt2:=0;
 for i:=1 to length(wname) do
  if wname[i] in ['A'..'Z','a'..'z','0'..'9'] then inc(cnt1)
   else inc(cnt2);
 if cnt1<4 then begin
  result:='^Name should contain at least 4 alphanumeric characters!^';
  exit;
 end;
 if cnt2>3 then begin
  result:='^Too many special characters!^';
  exit;
 end;
// name:=' '+name+' ';
 for i:=3 to length(wname) do
  if (wname[i-1]=wname[i]) and (wname[i-2]=wname[i]) and
     not (wname[i] in ['A'..'Z','a'..'z','0'..'9']) then begin
   result:='^Unallowed use of character^ "'+EncodeUTF8(wname[i])+'"';
   exit;
  end;
 wname:=lowercase(wname);
 if (copy(wname,1,5)='admin') or
    (copy(wname,1,9)='moderator') then result:='^This name is not allowed^';
end;

initialization
end.
