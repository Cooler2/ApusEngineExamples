// Здесь объекты с данными отчётов. Построение этих данный вызывается из DataThread
// Сами данные (когда готовы) используются при отрисовке отчётов
unit Reports;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface
uses MyServis;
const
 dtDouble = 1;
 dtInt = 2;
 dtStr = 3;
 dtDate = 4;

 // Список всех параметров для фильтров
 paramList:WideString=
   '00|параметр;'+
   // Непосредственные значения из БД
   '01|plr.created|Дата регистрации аккаунта;'+
   '02|plr.lastplayed|Дата последнего логина на сервере;'+
   '03|plr.level|Общий уровень;'+
   '04|plr.tags|Строка тэгов;'+
   '05|plr.guild|Строка тэгов;'+
   '06|plr.flags|Флаги;'+
   '07|plr.wins|Кол-во побед;'+
   '08|plr.loses|Кол-во поражений;'+
   '09|plr.speciality|Специальность;'+
   // Значения из сопутствующих таблиц
   '11|plr.client_lang|Последний выбранный язык клиента;'+
   '12|plr.regCountry|Страна регистрации аккаунта по IP;'+
   // Имущество игрока
   '21|plr.gold|Золото;'+
   '22|plr.gems|Кристаллы;'+
   '23|plr.AP|Astral Power;'+
   '24|plr.cards_count|Кол-во карт;'+
   // Производные (вычисляемые) значения
   '41|plr.steam|Игрок из Steam? 1 : 0;'+
   '42|plr.donated|Общая сумма внесённых игроком денег (USD);'+
   // Таблица платежей
   '51|pay.date|Дата/время совершения платежа;'+
   '52|pay.amountUSD|Сумма в USD;'+
   '53|pay.item|Что было оплачено;'+
   '54|pay.currency|Валюта оплаты;'+
   '55|pay.country|Страна оплаты;'+
   '56|pay.method|Где/как совершён платёж';

 // список всех операций для фильтров
 operationList:WideString=
     '0|=;'+
     '1|<>;'+
     '2|>;'+
     '3|<;'+
     '4|>=;'+
     '5|<=;'+
     '11|contains|Содержит указанную подстроку (без учёта регистра);'+
     '12|!contains|НЕ содержит указанную подстроку (без учёта регистра);'+
     '13|contains_CS|Содержит указанную подстроку (с учётом регистра);'+
     '14|!contains_CS|НЕ содержит указанную подстроку (с учётом регистра);'+
     '15|starts|Начинается с подстроки (без учёта регистра);'+
     '16|!starts|Не начинается с подстроки (без учёта регистра)';

 groupColors:array[0..3] of cardinal=($FF600000,$FF002070,$FF006020,$FF605000);
 accountAgeList:array[0..17] of integer=(1,2,3,5,7,10,14,21,28,35,42,49,56,63,70,77,84,91);

type
 TCondition=record
  parameter,oper:integer;
  value:AnsiString;
 end;

 TGroup=record
  conditions:array of TCondition;
 end;

 // Полные настройки отчёта
 TReportSettings=record
  rType:integer;
  groups:array of TGroup;
  function ExportToString:AnsiString;
  procedure ImportFromString(st:AnsiString);
 end;

 TReportData=class
  ready:boolean;
  mask:array[0..3] of ByteArray; // маска записей по фильтрам (а какие именно записи - зависит уже от типа отчёта)
  constructor Create;
  procedure ExportData(group:byte); virtual; // по дефолту экспортирует юзеров
  procedure Build(rs:TReportSettings); virtual;
 end;

 TPlayersOverview=class(TReportData)
  procedure Build(rs:TReportSettings); override;
 end;

 TPaymentsOverview=class(TReportData)
  procedure Build(rs:TReportSettings); override;
 end;

 TPaymentsReportData=class(TReportData)
  procedure Build(rs:TReportSettings); override;
 end;

 TNewPlayersData=class(TReportData)
  procedure Build(rs:TReportSettings); override;
 end;

 var
  curReportData:TReportData;
  playersOverview:TPlayersOverview;
  newPlayersData:TNewPlayersData;
  PaymentsOverview:TPaymentsOverview;
  paymentsReportData:TPaymentsReportData;

implementation
 uses
{$IFnDEF FPC}
  windows,
{$ELSE}
  LCLIntf, LCLType, LMessages,
{$ENDIF}
  SysUtils,Data,UICharts,Structs,EngineAPI;

const
 monthNames:array[1..12] of AnsiString=('JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC');

 // Проверяет выполняется ли указанное условие над данными операндами
 function CheckCondition(dType,oper:integer;aD,bD:double;aI,bI:int64;aSt,bSt,bStLc:AnsiString):boolean;
  begin
   result:=true;
   case dType of
    // Даты и вещественные числа
    dtDouble,dtDate:begin
       case oper of
        0:if aD<>bD then result:=false;
        1:if aD=bD then result:=false;
        2:if aD<=bD then result:=false;
        3:if aD>=bD then result:=false;
        4:if aD<bD then result:=false;
        5:if aD>bD then result:=false;
       end;
      end;
    // Целые числа
    dtInt:begin
       case oper of
        0:if aI<>bI then result:=false;
        1:if aI=bI then result:=false;
        2:if aI<=bI then result:=false;
        3:if aI>=bI then result:=false;
        4:if aI<bI then result:=false;
        5:if aI>bI then result:=false;
       end;
      end;
    // Строки
    dtStr:begin
       case oper of
        0:if aSt<>bSt then result:=false;
        1:if aSt=bSt then result:=false;
        2:if aSt<=bSt then result:=false;
        3:if aSt>=bSt then result:=false;
        4:if aSt<bSt then result:=false;
        5:if aSt>bSt then result:=false;
        11:if pos(bStLc,lowercase(aSt))=0 then result:=false;
        12:if pos(bStLc,lowercase(aSt))>0 then result:=false;
        13:if pos(bSt,aSt)=0 then result:=false;
        14:if pos(bSt,aSt)>0 then result:=false;
        15:if bStLc<>copy(lowercase(aSt),1,length(bStLc)) then result:=false;
        16:if bStLc=copy(lowercase(aSt),1,length(bStLc)) then result:=false;
       end;
      end;
    end;
  end;

 procedure GetParamValue(parameter:integer;value:AnsiString;out dType:integer;out bD:double;out bI:int64;out bSt:AnsiString;out bStLc:AnsiString);
  begin
   case parameter of
    // Даты
    1,2,51:begin bD:=GetDateFromStr(value); dType:=dtDate; end;
    // Целые числа
    3,41,7,8,9,21,22,23,34:begin bI:=StrToIntDef(value,0); dType:=dtInt; end;
    // Строки
    4,5,6,11,12,13,53,54,55,56:begin bSt:=value; bStLc:=lowercase(value); dType:=dtStr; end;
    // Вещественные числа
    42,52:begin bD:=StrToFloatDef(value,0); dType:=dtDouble; end;
   end;
  end;

 // Строит маску аккаунтов, подходящих выбранному фильтру (1 либо 0)
 function FilterUsers(group:TGroup):ByteArray;
  var
   i,c:integer;
   dType:integer; // 1 - double (datetime), 2 - int64, 3 - AnsiString
   aI,bI:int64;
   aD,bD:double;
   aSt,bSt,bStLc:AnsiString;
  begin
   SetLength(result,length(players));
   // все игроки кроме мусора
   for i:=0 to high(players) do begin
    if players[i].name<>'' then result[i]:=1 else result[i]:=0;
    if pos('@astralheroes.com',players[i].email)>0 then result[i]:=0;
    if (pos('Mage',players[i].name)>0) and (pos('junk',players[i].email)>0) and
       (pos('@yahoo.com',players[i].email)>0) then result[i]:=0;
   end;

   // Проверка всех условий
   for c:=0 to high(group.conditions) do
    with group.conditions[c] do begin
     if not (parameter in [1..49]) then continue;

     // Тип второго операнда и его значение
     GetParamValue(parameter,value,dType,bD,bI,bSt,bStLc);
     if (dType<>3) and (value='') then continue; // значение - пустая строка, а должно быть число или что-то ещё - значит условие некорректное и всегда верно

     // Проход по всем игрокам
     for i:=0 to high(players) do begin
      // Значение первого операнда
      case parameter of
       1:aD:=players[i].created;
       2:aD:=players[i].lastvisit;
       3:aI:=players[i].level[0];
       4:aSt:=players[i].tags;
       5:aSt:=players[i].guild;
       6:aSt:=players[i].flags;
       7:aI:=players[i].wins[0];
       8:aI:=players[i].loses[0];
       9:aI:=players[i].speciality;
       11:aSt:=players[i].clientLang;
       12:aSt:=players[i].regCountry;
       21:aI:=players[i].gold;
       22:aI:=players[i].gems;
       23:aI:=players[i].AP;
       24:aI:=players[i].cardsCount;
       41:aI:=players[i].isSteam;
       42:aD:=players[i].paidAmount;
      end;

      // Проверка условия для данного игрока
      if not CheckCondition(dType,oper,aD,bD,aI,bI,aSt,bSt,bStLc) then result[i]:=0;
     end; // конец прохода по игрокам
    end; // with
  end;

 // Заполняет массив PlayerID->сколько заплатил (в USD)
 function UsersPaid:FloatArray;
  var
   i,id:integer;
   v:double;
  begin
   SetLength(result,length(players));
   for i:=1 to high(payments) do begin
    v:=payments[i].amount;
    if payments[i].currency='RUB' then v:=v/64; // курс RUB - хорошо бы как-то соотносить с датой
    id:=payments[i].playerID;
    if (id>0) and (id<=high(result)) then
     result[id]:=result[id]+v;
   end;
  end;

 // Строит маску платежей, подходящих выбранному фильтру
 function FilterPayments(group:TGroup):ByteArray;
  var
   i,c:integer;
   dType:integer; // 1 - дата, 2 - строка
   aI,bI:int64;
   aD,bD:double;
   aSt,bSt,bStLc:AnsiString;
  begin
   SetLength(result,length(payments));
   for i:=0 to high(payments) do result[i]:=1;

   // Проверка всех условий
   for c:=0 to high(group.conditions) do
    with group.conditions[c] do begin
     if not (parameter in [51..56]) then continue;
     // Тип второго операнда и его значение
     GetParamValue(parameter,value,dType,bD,bI,bSt,bStLc);
     // Проход по всем платежам
     for i:=0 to high(payments) do begin
      // Значение первого операнда
      case parameter of
       51:aD:=payments[i].created;
       52:aD:=payments[i].amountUSD;
       53:aSt:=payments[i].itemCode;
       54:aSt:=payments[i].currency;
       55:aSt:=payments[i].country;
       56:aSt:=payments[i].payMethod;
      end;
      if not CheckCondition(dType,oper,aD,bD,aI,bI,aSt,bSt,bStLc) then result[i]:=0;
     end; // конец прохода
    end; // with
  end;

{ TPlayersOverview }

procedure TPlayersOverview.Build(rs:TReportSettings);
 var
  s,i,j,k:integer;
  table:TUISimpleTable;
  count,count2,count3,count4,count5,count6:integer;
  revenue:single;
  st,st1,st2,st3:AnsiString;
  tab:TUITable;
  hash:array[0..3] of TSimpleHashS; // значения в таблице
  keys:TSimpleHashS; // строки
  sa:AStringArr;
  rChart:TUIRealChart;
  vx,vy:FloatArray;
 begin
  inherited;
  for s:=0 to high(rs.groups) do
   mask[s]:=FilterUsers(rs.groups[s]);

  table:=UISimpleTable('Table02_1');
  table.ClearData;
  for s:=0 to high(rs.groups) do begin
   count:=0;
   count2:=0;
   revenue:=0;
   for i:=1 to high(mask[s]) do
    if mask[s,i]>0 then begin
     inc(count);
     if players[i].paidAmount>0 then begin
      inc(count2);
      revenue:=revenue+players[i].paidAmount;
     end;
    end;
   if count>0 then st1:=FloatToStrF(100*count2/count,ffFixed,4,2)+'%' else st1:='--';
   if count2>0 then st2:=FormatMoney(revenue/count2,2)+'$' else st2:='--';
   if count>0 then st3:=FormatMoney(revenue/count,2)+'$' else st3:='--';

   table.AddRow(Format('%s|%s|%s|%s|%s|%s',
    [FormatInt(count),FormatInt(count2),st1,FormatMoney(revenue,0),st2,st3]));
  end;

  // Retention
  table:=UISimpleTable('Table02_2');
  table.ClearData;
  for s:=0 to high(rs.groups) do begin
   count:=0; count2:=0; count3:=0; count4:=0; count5:=0; count6:=0;
   for i:=1 to high(mask[s]) do
    if mask[s,i]>0 then begin
     inc(count);
     if players[i].campaignWins>=15 then inc(count2);
     if players[i].lastvisit>players[i].created+1 then inc(count3);
     if players[i].lastvisit>players[i].created+3 then inc(count4);
     if players[i].lastvisit>players[i].created+10 then inc(count5);
     if players[i].lastvisit>players[i].created+30 then inc(count6);
    end;

   if count>0 then
    table.AddRow(FloatToStrF(100*count2/count,ffFixed,4,2)+'%|'+
     FloatToStrF(100*count3/count,ffFixed,4,2)+'%|'+
     FloatToStrF(100*count4/count,ffFixed,4,2)+'%|'+
     FloatToStrF(100*count5/count,ffFixed,4,2)+'%|'+
     FloatToStrF(100*count6/count,ffFixed,4,2)+'%')
   else
    table.AddRow('--|--|--|--|--');
  end;

  // Players tags
  tab:=UITable('PlayersTagsTable');
  tab.Reset;
  tab.AddColumn(80,'Tag',taLeft,tctString);
  // Считаем сколько раз какие теги встречаются
  keys.Init(100);
  for s:=0 to high(rs.groups) do begin
   tab.AddColumn(30,'#'+inttostr(s+1),taCenter,tctNumber);
   hash[s].Init(100);
   for i:=0 to high(players) do
    if mask[s,i]>0 then begin
     sa:=splitA(';',lowercase(players[i].tags));
     for j:=0 to high(sa) do
      if sa[j]<>'' then begin
       hash[s].Add(sa[j],1);
       keys.Put(sa[j],1);
      end;
    end;
  end;

  for i:=0 to keys.count-1 do begin
   st1:=keys.keys[i];
   st2:=st1;
   while (length(st2)>0) and (st2[length(st2)] in ['0'..'9']) do SetLength(st2,length(st2)-1);
   tab.AddRow(18,st2,st1);
   for s:=0 to high(rs.groups) do
    if hash[s].HasValue(st1) then
     tab.AddCell(inttostr(hash[s].Get(st1)))
    else
     tab.AddCell('0');
  end;
  tab.Commit(20,0,false);

  // OS
  tab:=UITable('PlayersOSTable');
  tab.Reset;
  tab.AddColumn(90,'OS',taLeft,tctString);
  // Считаем сколько раз какие значения встречаются
  keys.Init(100);
  for s:=0 to high(rs.groups) do begin
   tab.AddColumn(35,'#'+inttostr(s+1),taCenter,tctNumber);
   hash[s].Init(100);
   for i:=0 to high(players) do
    if mask[s,i]>0 then begin
     st:=players[i].osVersion;
     if st<>'' then begin
      hash[s].Add(st,1);
      keys.Put(st,1);
     end;
    end;
  end;

  for i:=0 to keys.count-1 do begin
   st1:=keys.keys[i];
   st2:=st1;
   if pos(' ',st2)>0 then SetLength(st2,pos(' ',st2)-1)
    else st2:=''; 
   tab.AddRow(18,st2,st1);
   for s:=0 to high(rs.groups) do
    if hash[s].HasValue(st1) then
     tab.AddCell(inttostr(hash[s].Get(st1)))
    else
     tab.AddCell('0');
  end;
  tab.Commit(20,0,false);

  // Videocards
  tab:=UITable('PlayersVideoTable');
  tab.Reset;
  tab.AddColumn(180,'Videocard',taLeft,tctString);
  // Считаем сколько раз какие значения встречаются
  keys.Init(100);
  for s:=0 to high(rs.groups) do begin
   tab.AddColumn(35,'#'+inttostr(s+1),taCenter,tctNumber);
   hash[s].Init(100);
   for i:=0 to high(players) do
    if mask[s,i]>0 then begin
     st:=players[i].videocard;
     if st<>'' then begin
      hash[s].Add(st,1);
      keys.Put(st,1);
     end;
    end;
  end;

  for i:=0 to keys.count-1 do begin
   st1:=keys.keys[i];
   st2:=st1;
   if pos(' ',st2)>0 then SetLength(st2,pos(' ',st2)-1)
    else st2:='other';
   tab.AddRow(18,st2,st1);
   for s:=0 to high(rs.groups) do
    if hash[s].HasValue(st1) then
     tab.AddCell(inttostr(hash[s].Get(st1)))
    else
     tab.AddCell('0');
  end;
  tab.Commit(20,0,false);

  // OpenGL
  tab:=UITable('PlayersOpenGLTable');
  tab.Reset;
  tab.AddColumn(70,'Ver.',taLeft,tctString);
  // Считаем сколько раз какие значения встречаются
  keys.Init(100);
  for s:=0 to high(rs.groups) do begin
   tab.AddColumn(35,'#'+inttostr(s+1),taCenter,tctNumber);
   hash[s].Init(100);
   for i:=0 to high(players) do
    if mask[s,i]>0 then begin
     st:=players[i].openGL;
     if st<>'' then begin
      hash[s].Add(st,1);
      keys.Put(st,1);
     end;
    end;
  end;

  for i:=0 to keys.count-1 do begin
   st1:=keys.keys[i];
   st2:=st1;
   if pos('.',st2)>0 then SetLength(st2,pos('.',st2)-1)
    else st2:='other'; 
   tab.AddRow(18,st2,st1);
   for s:=0 to high(rs.groups) do
    if hash[s].HasValue(st1) then
     tab.AddCell(inttostr(hash[s].Get(st1)))
    else
     tab.AddCell('0');
  end;
  tab.Commit(20,0,false);

  // Fame/battles
  SetLength(vX,length(players));
  SetLength(vY,length(players));
  for k:=0 to 3 do begin
   rChart:=UIRealChart('FameScatter'+inttostr(k));
   for s:=0 to high(rs.groups) do begin
    count:=0;
    for i:=0 to high(players) do
     if mask[s,i]>0 then begin
      vX[count]:=players[i].wins[k]+players[i].loses[k];
      vY[count]:=players[i].fame[k];
      if (vX[count]>=1000) or (vY[count]>=5000) then continue; // слишком далеко
      inc(count);
     end;
    rChart.Lock;
    SetLength(rChart.data,s+1);
    with rChart.data[s] do begin
     dataType:=cdtScatter;
     color:=round(20+23000/(count+100)) shl 24+groupColors[s] and $FFFFFF;
     xValues:=copy(vX,0,count);
     values:=copy(vY,0,count);
    end;
    rChart.Unlock;
   end;
  end;

  ready:=true;
 end;

{ TPlayerBaseData }

procedure TNewPlayersData.Build(rs: TReportSettings);
var
 chartW,chartM:TUISimpleChart;
 s,i,j,plrID,idx:integer;
 year,day,week,month,curMonth,curWeek:word;
 firstWeek,dd:TDateTime;
 plrMask:ByteArray;
 wR,mR:array[0..200] of integer;
 dSize:integer;
begin
 inherited;
 dSize:=28;
 chartW:=UISimpleChart('WeeklyReg');
 chartM:=UISimpleChart('MonthlyReg');
 firstWeek:=EncodeDate(2014,1,6); // первый день начальной недели
 DecodeDate(Now,year,month,day);
 curMonth:=12*(year-2014)+month;
 curWeek:=(trunc(now)-trunc(firstWeek)) div 7;

 chartW.Lock;
 with chartW do begin
  SetLength(names,dSize);
  for i:=0 to high(names) do begin
   week:=curWeek-high(names)+i;
   dd:=firstWeek+week*7;
   names[i]:=FormatDateTime('dd.mm',dd);
  end;
 end;
 chartW.Unlock;

 chartM.Lock;
 with chartM do begin
  SetLength(names,dSize);
  for i:=0 to high(names) do begin
   month:=word(curMonth-high(names)+i);
   names[i]:=monthNames[1+((month+11) mod 12)];
  end;
 end;
 chartM.Unlock;

 // Построим данные для каждой группы
 for s:=0 to high(rs.groups) do begin
  plrMask:=FilterUsers(rs.groups[s]);
  fillchar(wR,sizeof(wR),0);
  fillchar(mR,sizeof(MR),0);

  for i:=0 to high(players) do begin
   if plrMask[i]=0 then continue;
   DecodeDate(players[i].created,year,month,day);
   if year<2015 then continue;
   month:=12*(year-2014)+month;
   month:=curMonth-month;
   if (month>=0) and (month<dSize) then inc(mR[month]);
   week:=(trunc(players[i].created)-trunc(firstWeek)) div 7;
   week:=curWeek-week;
   if (week>=0) and (week<dSize) then inc(wR[week]);
  end;

  // Add data set
  chartW.Lock;
  with chartW do begin
   SetLength(data,s+1);
   data[s].name:='Группа '+inttostr(s+1);
   data[s].dataType:=cdtBar;
   data[s].color:=groupColors[s];
   SetLength(data[s].values,dSize);
   for j:=0 to dSize-1 do
    data[s].values[j]:=wR[dSize-1-j];
  end;
  chartW.Unlock;

  chartM.Lock;
  with chartM do begin
   SetLength(data,s+1);
   data[s].name:='Группа '+inttostr(s+1);
   data[s].dataType:=cdtBar;
   data[s].color:=groupColors[s];
   SetLength(data[s].values,dSize);
   for j:=0 to dSize-1 do
    data[s].values[j]:=mR[dSize-1-j];
  end;
  chartM.Unlock;
 end;
end;

{ TPaymentsReportData }

procedure TPaymentsReportData.Build(rs: TReportSettings);
var
 s,i,j,l,cnt,age,plrID,idx:integer;
 plrMask,payMask:ByteArray;
 chart:TUISimpleChart;
 v:array[0..20] of single;
 sum:double;
begin
 inherited;
 // Построим данные для каждой группы
 chart:=UISimpleChart('PaymentsPerAge1');
 for s:=0 to high(rs.groups) do begin
  plrMask:=FilterUsers(rs.groups[s]);
  payMask:=FilterPayments(rs.groups[s]);

  l:=14;
  for i:=0 to l-1 do begin
   age:=i+1;
   sum:=0;
   // Просуммируем все платежи, которые игроки совершили в течение age суток с момента регистрации аккаунта
   for j:=0 to high(payments) do begin
    if payMask[j]=0 then continue;
    plrID:=payments[j].playerID;
    idx:=playerIDhash.Get(plrID);
    if (idx<0) or (idx>high(players)) then continue;
    if plrMask[idx]=0 then continue;
    if payments[j].created>players[idx].created+age then continue;
    if players[idx].created>Now-age then continue;
    sum:=sum+payments[j].amountUSD;
   end;
   // Посчитаем кол-во игроков, которые могли такие платежи совершить
   cnt:=0;
   for j:=0 to high(players) do
    if (plrMask[j]>0) and (players[j].created<Now-age) then inc(cnt);

   if cnt>0 then v[i]:=sum/cnt else v[i]:=0;
  end;

  with chart do begin
   Lock;
   SetLength(data,s+1);
   data[s].name:='Группа '+inttostr(s);
   data[s].dataType:=cdtLine;
   data[s].color:=groupColors[s];
   SetLength(data[s].values,l);
   for i:=0 to l-1 do data[s].values[i]:=v[i];
   Unlock;
  end;
 end;

 chart:=UISimpleChart('PaymentsPerAge2');
 for s:=0 to high(rs.groups) do begin
  plrMask:=FilterUsers(rs.groups[s]);
  payMask:=FilterPayments(rs.groups[s]);

  l:=14;
  for i:=0 to l-1 do begin
   age:=(i+1)*7;
   sum:=0;
   // Просуммируем все платежи, которые игроки совершили в течение age суток с момента регистрации аккаунта
   for j:=0 to high(payments) do begin
    if payMask[j]=0 then continue;
    plrID:=payments[j].playerID;
    idx:=playerIDhash.Get(plrID);
    if (idx<0) or (idx>high(players)) then continue;
    if plrMask[idx]=0 then continue;
    if payments[j].created>players[idx].created+age then continue;
    if players[idx].created>Now-age then continue;
    sum:=sum+payments[j].amountUSD;
   end;
   // Посчитаем кол-во игроков, которые могли такие платежи совершить
   cnt:=0;
   for j:=0 to high(players) do
    if (plrMask[j]>0) and (players[j].created<Now-age) then inc(cnt);

   if cnt>0 then v[i]:=sum/cnt else v[i]:=0;
  end;

  with chart do begin
   Lock;
   SetLength(data,s+1);
   data[s].name:='Группа '+inttostr(s);
   data[s].dataType:=cdtLine;
   data[s].color:=groupColors[s];
   SetLength(data[s].values,l);
   for i:=0 to l-1 do data[s].values[i]:=v[i];
   Unlock;
  end;
 end;

end;

{ TPaymentsOverview }

procedure TPaymentsOverview.Build(rs: TReportSettings);
var
 chartW,chartM:TUISimpleChart;
 s,i,j,plrID,idx:integer;
 plrMask,payMask:ByteArray;
 wR,mR:array[0..200] of single;
 year,day,week,month,curMonth,curWeek:word;
 firstWeek,dd:TDateTime;
begin
 inherited;
 chartW:=UISimpleChart('WeeklyRevenue');
 chartM:=UISimpleChart('MonthlyRevenue');
 firstWeek:=EncodeDate(2016,1,4);
 DecodeDate(Now,year,month,day);
 curMonth:=12*(year-2016)+month;
 curWeek:=(trunc(now)-trunc(firstWeek)) div 7;

 chartW.Lock;
 with chartW do begin
  SetLength(names,20);
  for i:=0 to high(names) do begin
   week:=curWeek-high(names)+i;
   dd:=firstWeek+week*7;
   names[i]:=FormatDateTime('dd.mm',dd);
  end;
 end;
 chartW.Unlock;

 chartM.Lock;
 with chartM do begin
  SetLength(names,20);
  for i:=0 to high(names) do begin
   month:=word(curMonth-high(names)+i);
   names[i]:=monthNames[1+((month+11) mod 12)];
  end;
 end;
 chartM.Unlock;

 // Построим данные для каждой группы
 for s:=0 to high(rs.groups) do begin
  plrMask:=FilterUsers(rs.groups[s]);
  payMask:=FilterPayments(rs.groups[s]);
  fillchar(wR,sizeof(wR),0);
  fillchar(mR,sizeof(MR),0);

  for i:=0 to high(payments) do begin
   if payMask[i]=0 then continue;
   plrID:=payments[i].playerID;
   idx:=playerIDhash.Get(plrID);
   if (idx>=0) and (idx<=high(players)) then
    if plrMask[idx]=0 then continue;
   // номер месяца и номер недели относительно текущих
   DecodeDate(payments[i].created,year,month,day);
   month:=12*(year-2016)+month;
   month:=curMonth-month;
   if (month>=0) and (month<20) then mR[month]:=mR[month]+payments[i].amountUSD;
   week:=(trunc(payments[i].created)-trunc(firstWeek)) div 7;
   week:=curWeek-week;
   if (week>=0) and (week<20) then wR[week]:=wR[week]+payments[i].amountUSD;
  end;
  // Add data set
  chartW.Lock;
  with chartW do begin
   SetLength(data,s+1);
   data[s].name:='Группа '+inttostr(s+1);
   data[s].dataType:=cdtBar;
   data[s].color:=groupColors[s];
   SetLength(data[s].values,20);
   for j:=0 to 19 do
    data[s].values[j]:=wR[19-j];
  end;
  chartW.Unlock;

  chartM.Lock;
  with chartM do begin
   SetLength(data,s+1);
   data[s].name:='Группа '+inttostr(s+1);
   data[s].dataType:=cdtBar;
   data[s].color:=groupColors[s];
   SetLength(data[s].values,20);
   for j:=0 to 19 do
    data[s].values[j]:=mR[19-j];
  end;
  chartM.Unlock;
 end;
end;

procedure ExportPlayers(mask:ByteArray);
var
 i:integer;
 data:AnsiString;
begin
 for i:=0 to high(players) do
  if mask[i]>0 then begin
   data:=data+join([players[i].id, players[i].name, players[i].email, players[i].guild, players[i].flags, players[i].paidAmount,
     players[i].isSteam, FormatDateTime('yyyy-mm-dd hh:nn:ss',players[i].created),
     FormatDateTime('yyyy-mm-dd hh:nn:ss',players[i].lastvisit),
     FormatDateTime('yyyy-mm-dd hh:nn:ss',players[i].premium), players[i].avatar, players[i].gold,
     players[i].gems, players[i].AP, players[i].clientLang],#9)+#13#10;
  end;
  if length(data)>0 then
   SaveFile('players.csv',@data[1],length(data))
  else
   ShowMessage('No records!','Oops!');
end;

{ TReportData }

procedure TReportData.Build(rs: TReportSettings);
begin
 ready:=false;
end;

constructor TReportData.Create;
begin
 ready:=false;
end;

procedure TReportData.ExportData(group: byte);
begin
 ExportPlayers(mask[group-1]);
end;

{ TReportSettings }

// STR=ReportType#0(group1)#0...#0(groupN)
// Group=(Condition1)#1...#1(ConditionN)
// Condition=parameter#2operation#2value
function TReportSettings.ExportToString: AnsiString;
var
 i,j:integer;
 st:AnsiString;
begin
 result:=IntToStr(rType);
 for i:=0 to high(groups) do begin
  st:='';
  with groups[i] do
   for j:=0 to high(conditions) do begin
    if j>0 then st:=st+' | ';
    st:=st+Format('%d : %d : %s',[conditions[j].parameter,conditions[j].oper,conditions[j].value]);
   end;
  result:=result+' ||| '+st;
 end;
end;

procedure TReportSettings.ImportFromString(st: AnsiString);
var
 i,j:integer;
 sa,sb,sc:AStringArr;
begin
 sa:=splitA(' ||| ',st);
 rType:=StrToIntDef(sa[0],0);
 SetLength(groups,length(sa)-1);
 for i:=1 to high(sa) do with groups[i-1] do begin
  sb:=splitA(' | ',sa[i]);
  SetLength(conditions,length(sb));
  for j:=0 to high(sb) do with conditions[j] do begin
   sc:=splitA(' : ',sb[j]);
   if length(sc)>=3 then begin
    parameter:=StrToIntDef(sc[0],0);
    oper:=StrToIntDef(sc[1],0);
    value:=sc[2];
   end else begin
    parameter:=0;
    oper:=0;
    value:='';
   end;
  end;
 end;
end;

end.
