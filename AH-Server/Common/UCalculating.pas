
// Author: Alexey Stankevich (Apus Software)
unit UCalculating;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

const MPValues:array[1..10] of integer=(800,860,925,1000,1075,1150,1225,1300,1375,1450);

// победителю начислить стока экспа, проигравшему отнять на 1 меньше.
function FameForClassic(winnerFame,loserFame:integer):integer;
function FameForCustomized(winnerFame,loserFame:integer):integer;
function FameForDraft(winnerFame,loserFame:integer):integer;
function FameForWin(winnerFame,loserFame:integer;p:extended):integer;

function CalcLevel(fame:integer):integer;
function CalcFame(level:integer):integer;
// Total fame
function CalcPlayerFame(clsFame,custFame,draftFame:integer):integer;

function CalcPlayerTitle(campaignWins,ownedCards:integer):integer;

procedure CreateTables; // создаёт файл с табличками

function DailyGuildQuestWins(level:integer;lazyHeroesPerk:boolean):integer;

function CaravanResetGoldCost(caravanType:integer;remainingTime:double):integer;
function CanDuel(level1,level2:integer):boolean;


implementation
uses sysutils,math;

var
 fameLevel:array[0..100] of integer;

// время в сутках
function CaravanResetGoldCost(caravanType:integer;remainingTime:double):integer;
begin
 remainingtime:=remainingtime*24;
 if caravantype=1 then
 begin
  if remainingtime>67 then
   result:=80
  else
   result:=round(100*(remainingtime+3)/70);
 end else
 begin
  if remainingtime>44 then
   result:=40
  else
   result:=round(60*(remainingtime+2)/46);
 end;
end;

function CalcPlayerTitle(campaignWins,ownedCards:integer):integer;
begin
 result:=1;
 if campaignWins<3 then exit;
 result:=2;
 if ownedCards>=100 then result:=3;
 if ownedCards>=200 then result:=4;
 if ownedCards>=300 then result:=5;
 if ownedCards>=400 then result:=6;
end;

function calculatemax(l1,l2:integer):integer;
begin
 if l1>l2 then l1:=l2;
 if (l1>10) then result:=10 else
 if (l1<4) then result:=4 else
  result:=l1;
end;

function exptonextlevel(level:integer):integer;
const
 me:array[1..10] of integer=(0,100,250,500,800,1200,1600,2000,2500,3000);
begin
 if level<=8 then
  result:=me[level+1]-me[level]
 else
  result:=500;
end;

function CalcPlayerFame(clsFame,custFame,draftFame:integer):integer;
 var
  i,minexp,midexp,maxexp:integer;
 begin
  maxexp:=clsFame;
  minexp:=custFame;
  midexp:=draftFame;
  if (minexp>midexp) and (minexp>maxexp) then begin
   i:=maxexp; maxexp:=minexp; minexp:=i;
  end;
  if (midexp>minexp) and (midexp>maxexp) then begin
   i:=maxexp; maxexp:=midexp; midexp:=i;
  end;
  if (midexp<minexp) then begin
   i:=midexp; midexp:=minexp; minexp:=i;
  end;
  result:=maxexp+midexp*2 div 10+minexp div 10;
  if draftfame<maxexp then
   inc(result,draftfame div 10)
  else
   inc(result,midexp div 10)
 end;

function CalcLevel(fame:integer):integer;
 const
  me:array[0..9] of integer=(0,100,250,500,800,1200,1600,2000,2500,3000);
 begin
  try
   result:=0;
   if fame>=3000 then begin
    result:=10+(fame-3000) div 500;
   end else
    while fame>=me[result] do inc(result);
  except
  end;
 end;

function CalcFame(level:integer):integer;
 begin
  result:=fameLevel[level];
 end;

function FameForClassic(winnerFame,loserFame:integer):integer;
begin
 result:=FameForWin(winnerFame,loserFame,0.7);
end;

function FameForCustomized(winnerFame,loserFame:integer):integer;
begin
 result:=FameForWin(winnerFame,loserFame,0.5);
end;

function FameForDraft(winnerFame,loserFame:integer):integer;
begin
 result:=FameForWin(winnerFame,loserFame,0.58);
end;

function FameForWin(winnerFame,loserFame:integer;p:extended):integer;
var d,max,winnerLevel,loserLevel:integer;
    k,t1,t2:extended;
begin
 winnerLevel:=CalcLevel(winnerFame);
 loserLevel:=CalcLevel(loserFame);
 d:=winnerlevel-loserlevel;
 max:=calculatemax(winnerlevel,loserlevel);
 t1:=50*exp(ln(p)*d/max);
 t2:=50*exp(ln(p)*(-d)/max);
 if t1<25 then
  t1:=25;
 if t2<25 then
  t2:=25;
 result:=round((100*t1)/(t1+t2));
 if result<11 then
  result:=result+(11-result)*2 div 3;
end;

  function CanDuel(level1,level2:integer):boolean;
    var q:integer;
   begin
    if level1<level2 then begin
      q:=level1;
      level1:=level2;
      level2:=q;
    end;
    result:=level1-level2<=2+(level2 div 3);

{    // 1-st case
    if level1<=level2+3 then
      result:=true
    else
    // 2-nd case
    if level1>level2+10 then begin
//     if level2<10 then
      result:=false
//     else
//      result:=true;
    end
    else
    // 3-rd case
    if level1<=level2*2 then
      result:=true
    else
      result:=false;}
   end;

procedure CreateTables;
var
 f:text;
 i,j:integer;
 fame1,fame2:integer;
begin
 assign(f,'fameTable.htm');
 rewrite(f);
 writeln(f,'<table border=1 cellspacing=0 cellpadding=1><tr><td>');
 for j:=-10 to 10 do writeln(f,'<td>',j);
 for i:=1 to 25 do begin
  write(f,'<tr><td>',i);
  for j:=-10 to 10 do begin
   write(f,'<td>');
   if i+j<1 then continue;
   fame1:=CalcFame(i);
   fame2:=CalcFame(i+j);
   if canDuel(i,i+j) then write(f,'<div class=Mode1>',FameForCustomized(fame1,fame2),'</div>',
    '<div class=Mode2>',FameForClassic(fame1,fame2),'</div>',
    '<div class=Mode3>',FameForDraft(fame1,fame2),'</div>');
  end;
  writeln(f);
 end;
 writeln(f,'</table>');
 close(f);
end;

function DailyGuildQuestWins(level:integer;lazyHeroesPerk:boolean):integer;
begin
 result:=18+level*2;
 if lazyHeroesPerk then
  result:=result div 2;
end;

var
 fame,lvl:integer;
initialization
 for fame:=0 to 1000 do begin
  lvl:=CalcLevel(fame*50);
  if (lvl<=high(fameLevel))and(famelevel[lvl]=0) then fameLevel[lvl]:=fame*50;
 end;

end.
