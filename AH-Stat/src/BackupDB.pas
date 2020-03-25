unit BackupDB;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface
 var
  lastSyncDate:TDateTime;

 procedure LoadAllData;
 procedure BackupGameDB;
 procedure VerifyGameDB;
 procedure AbortBackup;

 procedure CalculateBotsWinrate;
 procedure CalculateWinrates;

implementation
uses
{$IFnDEF FPC}
  database,
{$ELSE}
{$ENDIF}
  SysUtils,Classes,MyServis,mainWnd,Data,NetCommon,UCalculating,Cnsts,structs;

type
 TSyncThread=class(TThread)
  onlyVerify:boolean;
  // Если начинается с '+' - дописывается к последней строке
  // Если начинается с '-' - заменяет собой последнюю строку
  procedure AddLogMsg(st: String8);
  procedure Execute; override;
 end;

 TLoadDataThread=class(TThread)
  procedure AddLogMsg(st: String8);
  procedure Execute; override;
 end;

var
 syncThread:TSyncThread;
 loadThread:TLoadDataThread;
 db:TMySQLDatabase;

procedure DataAddLogMsg(st:String8);
 begin
  if syncThread<>nil then
   syncThread.AddLogMsg(st)
  else
  if loadThread<>nil then
   loadThread.AddLogMsg(st)
 end;

procedure BackupGameDB;
 begin
  syncThread:=TSyncThread.Create(true);
  syncThread.onlyVerify:=false;
  syncThread.Resume;
 end;

procedure VerifyGameDB;
 begin
  syncThread:=TSyncThread.Create(true);
  syncThread.onlyVerify:=true;
  syncThread.Resume; end;

procedure AbortBackup;
 begin
  if syncThread<>nil then syncThread.Terminate;
 end;

procedure LoadAllData;
 begin
  loadThread:=TLoadDataThread.Create(false);
 end;

{ TSyncThread }
procedure TSyncThread.AddLogMsg(st: String8);
begin
 if (length(st)>0) and not (st[1] in ['+','-']) then LogMessage(st);
 mainForm.addLogStr:=st;
 Synchronize(MainForm.UpdateLog);
end;

procedure TLoadDataThread.AddLogMsg(st: String8);
begin
 LogMessage(st);
 mainForm.addLogStr:=st;
 Synchronize(MainForm.UpdateLog);
end;

procedure SaveLocalData(name:String8);
var
 fName,fNew:String8;
 count:integer;
begin
  // Сохранение данных в файл
  syncThread.AddLogMsg('Saving... ');
  fname:=DBPath+name+'.dat';
  fNew:=DBPath+name+'.new';
  count:=0;

  if name='duels' then count:=SaveAllDuels(fNew);
  if name='events' then count:=SaveAllEvents(fNew);
  if name='payments' then count:=SaveAllPayments(fNew);
  if name='players' then count:=SaveAllPlayers(fNew);
  if name='visits' then count:=SaveAllVisits(fNew);
  if name='guilds' then count:=SaveAllGuilds(fNew);
  if name='guildmembers' then count:=SaveAllGuildmembers(fNew);
  if name='guildlog' then count:=SaveAllGuildLog(fNew);

  if FileExists(fname) then DeleteFile(fname);
  RenameFile(fNew,fname);
  DeleteFile(fNew);
  syncThread.AddLogMsg('+done! Total: '+inttostr(count)+' records');
end;

procedure SyncDuelsTable;
var
 i,maxID,idx,p,count:integer;
 sa:AStringArr;
 fname,fNew:String8;
begin
 syncThread.AddLogMsg('Fetching duels...');
 maxID:=0;
 for i:=0 to high(duels) do
  if duels[i].id>maxID then maxID:=duels[i].id;

 count:=0;
 syncThread.AddLogMsg('0 records');
 repeat
  sa:=db.Query('SELECT id,date,dueltype,scenario,winner,loser,turns,duration,firstplr,'+
    'winnerLevel,loserLevel,winnerDeck,loserDeck,winnerFame,loserFame FROM duels WHERE id>'+inttostr(maxid)+' ORDER BY ID ASC LIMIT 5000');
  if db.rowCount=0 then break;
  inc(count,db.rowCount);

  idx:=length(duels);
  SetLength(duels,idx+db.rowCount);
  p:=0;
  for i:=0 to db.rowCount-1 do begin
   duels[idx+i].id:=StrToInt(sa[p]);
   maxID:=max2(maxID,duels[idx+i].id);
   duels[idx+i].date:=GetDateFromStr(sa[p+1]);
   duels[idx+i].dueltype:=StrToInt(sa[p+2]);
   duels[idx+i].scenario:=StrToInt(sa[p+3]);
   duels[idx+i].winner:=StrToInt(sa[p+4]);
   duels[idx+i].loser:=StrToInt(sa[p+5]);
   duels[idx+i].turns:=StrToInt(sa[p+6]);
   duels[idx+i].duration:=StrToInt(sa[p+7]);
   duels[idx+i].firstplr:=StrToInt(sa[p+8]);
   duels[idx+i].winnerlevel:=StrToInt(sa[p+9]);
   duels[idx+i].loserlevel:=StrToInt(sa[p+10]);
   if (sa[p+11]<>'') or (sa[p+12]<>'') then begin
    SetLength(duels[idx+i].decks,2);
    StrToDeck(sa[p+11],duels[idx+i].decks[1]);
    StrToDeck(sa[p+12],duels[idx+i].decks[0]);
   end else
    SetLength(duels[idx+i].decks,0);
   duels[idx+i].winnerFame:=StrToInt(sa[p+13]);
   duels[idx+i].loserFame:=StrToInt(sa[p+14]);
   inc(p,db.colCount);
  end;

  syncThread.AddLogMsg('-'+inttostr(count)+' records');
 until syncThread.Terminated;

 if count>0 then SaveLocalData('duels');
end;

procedure SyncEventsTable;
var
 i,maxID,idx,p,count:integer;
 sa:AStringArr;
 fname,fNew:String8;
begin
 syncThread.AddLogMsg('Fetching events...');
 maxID:=0;
 for i:=0 to high(events) do
  if events[i].id>maxID then maxID:=events[i].id;

 count:=0;
 syncThread.AddLogMsg('0 records');
 repeat
  sa:=db.Query('SELECT id,playerid,created,event,info FROM eventlog WHERE id>'+inttostr(maxid)+' ORDER BY ID ASC LIMIT 5000');
  if db.rowCount=0 then break;
  inc(count,db.rowCount);

  idx:=length(events);
  SetLength(events,idx+db.rowCount);
  p:=0;
  for i:=0 to db.rowCount-1 do begin
   events[idx+i].id:=StrToInt(sa[p]);
   maxID:=max2(maxID,events[idx+i].id);
   events[idx+i].playerID:=StrToInt(sa[p+1]);
   events[idx+i].created:=GetDateFromStr(sa[p+2]);
   events[idx+i].event:=sa[p+3];
   events[idx+i].info:=sa[p+4];
   inc(p,db.colCount);
  end;

  syncThread.AddLogMsg('-'+inttostr(count)+' records');
 until syncThread.Terminated;

 if count>0 then SaveLocalData('events');
end;

// Данные за текущие сутки НЕ запрашиваются
procedure SyncVisitsTable;
var
 i,maxID,idx,p,count:integer;
 sa:AStringArr;
 fname,fNew:String8;
begin
 syncThread.AddLogMsg('Fetching visits...');
 maxID:=0;
 for i:=0 to high(visits) do
  if visits[i].id>maxID then maxID:=visits[i].id;

 count:=0;
 syncThread.AddLogMsg('0 records');
 repeat
  sa:=db.Query('SELECT id,playerid,date,vid,ip,country,page,referer,tags FROM visits WHERE date(date)<date(Now()) AND id>'+inttostr(maxid)+' ORDER BY ID ASC LIMIT 3000');
  if db.rowCount=0 then break;
  inc(count,db.rowCount);

  idx:=length(visits);
  SetLength(visits,idx+db.rowCount);
  p:=0;
  for i:=0 to db.rowCount-1 do begin
   visits[idx+i].id:=StrToInt(sa[p]);
   maxID:=max2(maxID,visits[idx+i].id);
   visits[idx+i].playerID:=StrToIntDef(sa[p+1],0);
   visits[idx+i].date:=GetDateFromStr(sa[p+2]);
   visits[idx+i].vid:=StrToInt64Def(sa[p+3],0);
   visits[idx+i].ip:=sa[p+4];
   visits[idx+i].country:=sa[p+5];
   visits[idx+i].page:=sa[p+6];
   visits[idx+i].referer:=sa[p+7];
   visits[idx+i].tags:=sa[p+8];
   inc(p,db.colCount);
  end;

  syncThread.AddLogMsg('-'+inttostr(count)+' records');
 until syncThread.Terminated;

 if count>0 then SaveLocalData('visits');
end;


// Эта таблица скачивается целиком
procedure SyncPaymentsTable;
var
 i,maxID,idx,p,count:integer;
 sa:AStringArr;
 fname,fNew:String8;
begin
 syncThread.AddLogMsg('Fetching payments...');

 SetLength(payments,0); // Очищаем старые данные и начинаем с нуля

 count:=0;
 syncThread.AddLogMsg('0 records');
 //repeat
  sa:=db.Query('SELECT id,userid,created,username,itemCode,amount,currency,transaction,country,method '+
    'FROM payments WHERE completed=2');
  if db.rowCount=0 then exit;
  inc(count,db.rowCount);

  idx:=0;
  SetLength(payments,db.rowCount);
  p:=0;
  for i:=0 to db.rowCount-1 do begin
   payments[idx+i].id:=StrToInt(sa[p]);
   //maxID:=max2(maxID,payments[idx+i].id);
   payments[idx+i].playerID:=StrToInt(sa[p+1]);
   payments[idx+i].created:=GetDateFromStr(sa[p+2]);
   payments[idx+i].username:=sa[p+3];
   payments[idx+i].itemcode:=sa[p+4];
   payments[idx+i].amount:=StrToFloat(sa[p+5]);
   payments[idx+i].currency:=sa[p+6];
   payments[idx+i].transaction:=StrToInt64(sa[p+7]);
   payments[idx+i].country:=sa[p+6];
   payments[idx+i].method:=sa[p+6];
   inc(p,db.colCount);
  end;

  syncThread.AddLogMsg('-'+inttostr(count)+' records');
 //until syncThread.Terminated;

  SaveLocalData('payments');
end;

// Эта таблица скачивается целиком
procedure SyncPlayersTable;
var
 i,j,maxID,idx,p,count:integer;
 sa:AStringArr;
 fname,fNew,st:String8;
begin
 syncThread.AddLogMsg('Fetching players...');
 SetLength(players,0); // Очищаем старые данные и начинаем с нуля

 count:=0; maxID:=0;
 syncThread.AddLogMsg('0 records');
 repeat
  sa:=db.Query('SELECT id,name,email,pwd,flags,created,lastVisit,premium,avatar,gold,gems,astralPower,'+
    'insight,needInsight,customFame,classicFame,draftFame,level,customLevel,classicLevel,draftLevel,'+
    'customWins,classicWins,draftWins,customLoses,classicLoses,draftLoses,'+
    'draftTourWins,realname,location,about,tags,cards,referer,paramX,optionsFlags,'+
    'HP,speciality,campaignWins,room,quests,campaignLoses,friendlist,blacklist,missions,market,guild'+
    ' FROM players WHERE id>'+inttostr(maxID)+' ORDER BY id ASC LIMIT 500');
  if db.rowCount=0 then break;
  inc(count,db.rowCount);

  idx:=length(players);
  SetLength(players,idx+db.rowCount);
  p:=0;
  for i:=0 to db.rowCount-1 do try
   players[idx+i].id:=StrToInt(sa[p]);
   maxID:=max2(maxID,players[idx+i].id);
   players[idx+i].name:=sa[p+1];
   players[idx+i].email:=sa[p+2];
   players[idx+i].pwd:=sa[p+3];
   players[idx+i].flags:=sa[p+4];
   players[idx+i].created:=GetDateFromStr(sa[p+5]);
   players[idx+i].lastVisit:=GetDateFromStr(sa[p+6]);
   players[idx+i].premium:=GetDateFromStr(sa[p+7]);
   players[idx+i].avatar:=StrToInt(sa[p+8]);
   players[idx+i].gold:=StrToInt(sa[p+9]);
   players[idx+i].gems:=StrToInt(sa[p+10]);
   players[idx+i].AP:=StrToInt(sa[p+11]);
   players[idx+i].hero:=StrToInt(sa[p+12]);
   players[idx+i].needHero:=StrToInt(sa[p+13]);
   players[idx+i].fame[1]:=StrToInt(sa[p+14]);
   players[idx+i].fame[2]:=StrToInt(sa[p+15]);
   players[idx+i].fame[3]:=StrToInt(sa[p+16]);
   players[idx+i].level[0]:=StrToInt(sa[p+17]);
   players[idx+i].level[1]:=StrToInt(sa[p+18]);
   players[idx+i].level[2]:=StrToInt(sa[p+19]);
   players[idx+i].level[3]:=StrToInt(sa[p+20]);
   players[idx+i].wins[1]:=StrToInt(sa[p+21]);
   players[idx+i].wins[2]:=StrToInt(sa[p+22]);
   players[idx+i].wins[3]:=StrToInt(sa[p+23]);
   players[idx+i].loses[1]:=StrToInt(sa[p+24]);
   players[idx+i].loses[2]:=StrToInt(sa[p+25]);
   players[idx+i].loses[3]:=StrToInt(sa[p+26]);
   players[idx+i].dtWins:=StrToInt(sa[p+27]);
   players[idx+i].realname:=sa[p+28];
   players[idx+i].location:=sa[p+29];
   players[idx+i].about:=sa[p+30];
   players[idx+i].tags:=sa[p+31];
   players[idx+i].cards:=sa[p+32];
   players[idx+i].referer:=StrToIntDef(sa[p+33],0);
   players[idx+i].paramX:=StrToInt(sa[p+34]);
   players[idx+i].optFlags:=StrToInt(sa[p+35]);
   players[idx+i].HP:=StrToInt(sa[p+36]);
   players[idx+i].speciality:=StrToInt(sa[p+37]);
   players[idx+i].campaignWins:=StrToInt(sa[p+38]);
   players[idx+i].room:=StrToInt(sa[p+39]);
   players[idx+i].quests:=sa[p+40];
   players[idx+i].campaignLoses:=sa[p+41];
   players[idx+i].friendlist:=sa[p+42];
   players[idx+i].blacklist:=sa[p+43];
   players[idx+i].missions:=sa[p+44];
   players[idx+i].market:=sa[p+45];
   players[idx+i].guild:=sa[p+46];   
   inc(p,db.colCount);
   // вычисляемые значения
   with players[idx+i] do begin
    wins[0]:=wins[1]+wins[2]+wins[3];
    loses[0]:=loses[1]+loses[2]+loses[3];
    fame[0]:=CalcPlayerFame(fame[2],fame[1],fame[3]);
    while length(cards)<numcards do cards:=cards+'0';
    cardsCount:=0;
    for j:=1 to length(cards) do
     inc(cardsCount,byte(cards[j])-ord('0'));
   end;
  except
   on e:Exception do begin
    st:='';
    for j:=0 to 45 do st:=st+sa[p+j]+';';
    LogMessage('Error in row: '+e.message+' values: '+st);
   end;
  end;

  syncThread.AddLogMsg('-'+inttostr(count)+' records');
 until syncThread.Terminated;

 BuildPlayersIndex;
 SaveLocalData('players');
end;

// Эта таблица скачивается целиком
procedure SyncGuildsTable;
var
 i,maxID,idx,p,count:integer;
 sa:AStringArr;
 fname,fNew:String8;
begin
 syncThread.AddLogMsg('Fetching guilds...');

 SetLength(guilds,0); // Очищаем старые данные и начинаем с нуля

 count:=0;
 syncThread.AddLogMsg('0 records');
 
  sa:=db.Query('SELECT id,name,size,level,exp,treasures,bonuses,cards,flags FROM guilds');
  if db.rowCount=0 then exit;
  inc(count,db.rowCount);

  idx:=0;
  SetLength(guilds,db.rowCount);
  p:=0;
  for i:=0 to db.rowCount-1 do begin
   guilds[idx+i].id:=StrToInt(sa[p]);
   guilds[idx+i].name:=sa[p+1];
   guilds[idx+i].size:=StrToInt(sa[p+2]);
   guilds[idx+i].level:=StrToInt(sa[p+3]);
   guilds[idx+i].exp:=StrToInt(sa[p+4]);
   guilds[idx+i].treasures:=StrToInt(sa[p+5]);
   guilds[idx+i].bonuses:=sa[p+6];
   guilds[idx+i].cards:=sa[p+7];
   guilds[idx+i].flags:=StrToInt(sa[p+8]);
   inc(p,db.colCount);
  end;

  syncThread.AddLogMsg('-'+inttostr(count)+' records');

  SaveLocalData('guilds');
end;

// Эта таблица скачивается целиком
procedure SyncGuildMembersTable;
var
 i,maxID,idx,p,count:integer;
 sa:AStringArr;
 fname,fNew:String8;
begin
 syncThread.AddLogMsg('Fetching guild members...');

 SetLength(guildmembers,0); // Очищаем старые данные и начинаем с нуля

 count:=0;
 syncThread.AddLogMsg('0 records');

  sa:=db.Query('SELECT playerid,guild,rank,treasures,exp FROM guildmembers');
  if db.rowCount=0 then exit;
  inc(count,db.rowCount);

  idx:=0;
  SetLength(guildmembers,db.rowCount);
  p:=0;
  for i:=0 to db.rowCount-1 do begin
   guildmembers[idx+i].plrID:=StrToInt(sa[p]);
   guildmembers[idx+i].guildID:=StrToInt(sa[p+1]);
   guildmembers[idx+i].rank:=StrToInt(sa[p+2]);
   guildmembers[idx+i].treasures:=StrToInt(sa[p+3]);
   guildmembers[idx+i].exp:=StrToInt(sa[p+4]);
   inc(p,db.colCount);
  end;

  syncThread.AddLogMsg('-'+inttostr(count)+' records');

  SaveLocalData('guildmembers');
end;

// Эта таблица скачивается целиком
procedure SyncGuildLogTable;
var
 i,maxID,idx,p,count:integer;
 sa:AStringArr;
 fname,fNew:String8;
begin
 syncThread.AddLogMsg('Fetching guild log...');

 SetLength(guildlog,0); // Очищаем старые данные и начинаем с нуля

 count:=0;
 syncThread.AddLogMsg('0 records');

  sa:=db.Query('SELECT guild,date,msg FROM guildlog');
  if db.rowCount=0 then exit;
  inc(count,db.rowCount);

  idx:=0;
  SetLength(guildlog,db.rowCount);
  p:=0;
  for i:=0 to db.rowCount-1 do begin
   guildlog[idx+i].guildID:=StrToInt(sa[p]);
   guildlog[idx+i].date:=GetDateFromStr(sa[p+1]);
   guildlog[idx+i].msg:=sa[p+2];
   inc(p,db.colCount);
  end;

  syncThread.AddLogMsg('-'+inttostr(count)+' records');

  SaveLocalData('guildlog');
end;

// Поиск всевозможных косяков в данных
procedure VerifyData;
type
 TPlrMissions=record
  mCount:array[1..12] of byte;
 end;
const lvl:array[1..7] of integer=(3,5,10,15,20,25,30);
var
 i,n,j,k,idx,c,v,delta:integer;
 plrMissions:array of TPlrMissions;
 plrAddAP:array of byte;
 st,report:String8;
 hash:TSimpleHash;
 ia:IntArray;
 sa:AStringArr;
begin
 // Проверка игроков на пропущенные миссии
 syncThread.AddLogMsg('Checking missed missions...');
 st:='';
 SetLength(plrMissions,maxPlayerID+1);
 SetLength(plrAddAP,maxPlayerID+1);
 for i:=0 to high(events) do begin
  if (events[i].event='AP') and (pos('Level-',events[i].info)>0) then begin
   n:=events[i].playerID;
   if n<=0 then continue;
   j:=0;
   if pos('Level-3',events[i].info)>0 then j:=1;
   if pos('Level-5',events[i].info)>0 then j:=2;
   if pos('Level-10',events[i].info)>0 then j:=3;
   if pos('Level-15',events[i].info)>0 then j:=4;
   if pos('Level-20',events[i].info)>0 then j:=5;
   if pos('Level-25',events[i].info)>0 then j:=6;
   if pos('Level-30',events[i].info)>0 then j:=7;
   if pos('Level-40',events[i].info)>0 then j:=8;
   if pos('Level-50',events[i].info)>0 then j:=9;
   if pos('Level-75',events[i].info)>0 then j:=10;
   ASSERT(j>0,'mission index');
   ASSERT((n>0) and (n<length(plrMissions)),'player index = '+inttostr(n));
   inc(plrMissions[n].mCount[j]);
  end;
 end;
{ for i:=0 to high(plrMissions) do begin
  n:=0;
  for j:=6 downto 1 do begin
   if plrMissions[i].mCount[j]<n then begin
    idx:=playerIDhash.Get(i);
    ASSERT(idx>=0);
    st:=st+players[idx].name+', ';
    LogMessage(Format('Missed mission type %d for %s (id=%d)',[j,players[idx].name,players[idx].id]));
   end;
   n:=max2(n,plrMissions[i].mCount[j]);
  end;
 end;}
 for i:=0 to high(players) do begin
  idx:=players[i].id;
  if (idx<0) or (idx>high(plrMissions)) then begin
   sleep(0);
   continue;
  end;
  for j:=1 to 7 do begin
   n:=lvl[j]; c:=0;
   for k:=1 to 3 do
    if players[i].level[k]>=n then inc(c);
   if c>plrMissions[idx].mCount[j] then begin
    st:=st+players[i].name+', ';
    LogMessage(Format('Missed AP reward for level %d for %s (id=%d)',[n,players[i].name,players[i].id]));
    LogMessage(Format('INSERT INTO eventlog (created,playerid,event,info) values (Now(),%d,"AP","%d+5=%d;Level-%d");',
      [idx,players[i].AP+plrAddAP[idx],players[i].AP+plrAddAP[idx]+5,n]));
    inc(plrAddAP[idx],5);
    LogMessage(Format('UPDATE players SET astralpower=astralpower+5 WHERE id=%d;',[idx]));
   end;
  end;
 end;
 if st<>'' then begin
  syncThread.AddLogMsg('Missed missions for players: '+st);
 end;

 // Проверка начисления Astral Power
 syncThread.AddLogMsg('Checking Astral Power...');
 SetLength(ia,maxPlayerID+1);
 report:='';
 for i:=0 to high(events) do
  if events[i].event='AP' then begin
   st:='';
   sa:=splitA(';',events[i].info);
   j:=pos('+',sa[0]);
   v:=StrToInt(copy(sa[0],1,j-1));
   ASSERT((events[i].playerID>0) and (events[i].playerID<=maxPlayerID),'Bad PlayerID at event '+inttostr(i));
{   if ia[events[i].playerID]>0 then
    if ia[events[i].playerID]<>v then st:=Format('Initial value doesn''t match: %d <> %d (delta=%d)',
      [ia[events[i].playerID],v,v-ia[events[i].playerID]]);}
   if pos('Reward for #',sa[1])>0 then begin
    v:=StrToInt(copy(sa[1],14,10));
    if not (v in [9,17]) then st:='Invalid scenario - '+inttostr(v);
   end else
   if (pos('Cards=',sa[1])>0) or (pos('Level-',sa[1])>0) or (pos('Rollback for',sa[1])>0) then
   else st:='Incorrect reason!';

   if st<>'' then begin
    j:=playerIDhash.Get(events[i].playerID);
    report:=report+players[j].name+': '+st+#13#10+Format('%d plr=%d %s %s'#13#10#13#10,
     [events[i].id,events[i].playerID,FormatDateTime('yyyy.mm.dd hh:nn:ss',events[i].created),events[i].info]);
//    report:=report+Format('UPDATE players SET astralPower=astralPower-%d WHERE id=%d'#13#10,[,playerID]);
   end;
   delete(sa[0],1,pos('=',sa[0]));
   v:=StrToInt(sa[0]);
   ia[events[i].playerID]:=v;
  end;
  if report<>'' then begin
   syncThread.AddLogMsg('Wrong AP! See report for details...');
   SaveFile('Reports\BadAP.txt',@report[1],length(report));
  end;

 // Verify tables
 // Duels
 syncThread.AddLogMsg('Checking Duels table...');
 st:=''; report:='';
 hash.Init(length(duels));
 for i:=0 to high(duels) do begin
  v:=duels[i].id;
  if hash.HasValue(v) then
   st:=st+IntToStr(v)+';';
  hash.Put(v,1);
 end;
 if st<>'' then syncThread.AddLogMsg('WARN! Duplicated keys in duels table: '+copy(st,1,1000));
 // Events
 syncThread.AddLogMsg('Checking Events table...');
 st:=''; report:='';
 hash.Init(length(events));
 for i:=0 to high(events) do begin
  v:=events[i].id;
  if hash.HasValue(v) then st:=st+IntToStr(v)+';';
  hash.Put(v,1);
 end;
 if st<>'' then begin
  syncThread.AddLogMsg('WARN! Duplicated keys in events table: '+copy(st,1,1000));
  DumpEvents('Reports\events.txt');
 end;
 // Visits
 syncThread.AddLogMsg('Checking Visits table...');
 st:=''; report:='';
 hash.Init(length(visits));
 for i:=0 to high(visits) do begin
  v:=visits[i].id;
  if hash.HasValue(v) then begin
   st:=st+IntToStr(v)+';';
   j:=hash.Get(v);
   report:=report+Format('PREV: %d. id=%d vid=%d date=%s'#13#10,
     [j,visits[j].id,visits[j].vid,FormatDateTime('dd.mm.yy hh:nn:ss',visits[j].date)]);
   report:=report+Format('NEXT: %d. id=%d vid=%d date=%s'#13#10#13#10,
     [i,v,visits[i].vid,FormatDateTime('dd.mm.yy hh:nn:ss',visits[i].date)]);
  end;
  hash.Put(v,i);
 end;
 if st<>'' then begin
  syncThread.AddLogMsg('WARN! Duplicated keys in visits table: '+copy(st,1,1000));
  SaveFile('Reports\DuplicatedVisits.txt',@report[1],length(report));
 end;
end;

procedure TSyncThread.Execute;
begin
 try
  if not onlyVerify then begin
   AddLogMsg('Initializing MySQL connection...');
   // Init MySQL Connection
   db:=TMySQLDatabase.Create;
   db.logSelects:=true;
   db.logChanges:=true;
   db.Connect;
   if not db.connected then raise Exception.Create('DB connection failed: '+db.lastError);
   AddLogMsg('+ connected!');
   if not terminated then SyncPlayersTable;
   if not terminated then SyncPaymentsTable;
   if not terminated then SyncDuelsTable;

   if not terminated then SyncEventsTable;
   if not terminated then SyncVisitsTable;
   if not terminated then SyncGuildsTable;
   if not terminated then SyncGuildmembersTable;
   if not terminated then SyncGuildLogTable;

   db.Disconnect;
   db.Free;
  end;
  AddLogMsg('Verifying data consistency...');
  VerifyData;
  AddLogMsg('+ Done!');
  if not onlyVerify then
   AddLogMsg('Sync done!');
 except
  on e:Exception do AddLogMsg('Error: '+e.message);
 end;
 Synchronize(MainForm.SyncDone);
end;

// Загрузка всех локальных данных
procedure TLoadDataThread.Execute;
begin
 try
  AddLogMsg('Loading local data... ');

  LoadAllPlayers(DBPath+'players.dat');
  AddLogMsg(inttostr(length(players))+' players');

  LoadAllDuels(DBPath+'duels.dat');
  AddLogMsg(inttostr(length(duels))+' duels');

  LoadAllEvents(DBPath+'events.dat');
  AddLogMsg(inttostr(length(events))+' events');

  LoadAllPayments(DBPath+'payments.dat');
  AddLogMsg(inttostr(length(payments))+' payments');

  LoadAllVisits(DBPath+'visits.dat');
  AddLogMsg(inttostr(length(visits))+' visits');

  LoadAllGuilds(DBPath+'guilds.dat');
  AddLogMsg(inttostr(length(guilds))+' guilds');

  LoadAllGuildmembers(DBPath+'guildmembers.dat');
  AddLogMsg(inttostr(length(guildmembers))+' guildmembers');

  LoadAllGuildLog(DBPath+'guildlog.dat');
  AddLogMsg(inttostr(length(guildlog))+' guildlog records');

  AddLogMsg('Done!');
 except
  on e:exception do AddLogMsg('Loading error: '+e.message);
 end;
 Synchronize(MainForm.LoadingDone);
end;

procedure CalculateBotsWinrate;
var
 i,j,k,n:integer;
 startDate,endDate:TDateTime;
 stat:array[1..30,1..50,1..2] of integer;
 lvl:array[1..30] of integer;
 f:text;
begin
 n:=0;
 startDate:=GetDateFromStr('1.09.2018');
 endDate:=GetDateFromStr('1.10.2018');
 fillchar(stat,sizeof(stat),0);
 for i:=0 to high(duels) do
  with duels[i] do begin
   if (date<startDate) or (date>endDate) then continue;
   if (winner>=0) and (loser>=0) then continue;
   if dueltype<>1 then continue;
   if winner<0 then begin
    lvl[-winner]:=winnerLevel;
    inc(stat[winnerLevel,loserLevel,1]);
    inc(stat[winnerLevel,loserLevel,2]);
   end else
    inc(stat[loserLevel,winnerLevel,2]);
   inc(n);
  end;
 assign(f,'reports\winrates.txt');
 rewrite(f);
 for j:=1 to 30 do begin
  writeln(f,'Bot #',j,' level=',j);
  for i:=max2(1,j-2) to j+2 do write(f, i:6);
  writeln(f);
  for i:=max2(1,j-2) to j+2 do write(f, stat[j,i,1]:6);
  writeln(f);
  for i:=max2(1,j-2) to j+2 do write(f, stat[j,i,2]:6);
  writeln(f);
  for i:=max2(1,j-2) to j+2 do
   if stat[j,i,2]>1 then
    write(f, round(100*stat[j,i,1]/stat[j,i,2]):5,'%')
   else
    write(f, '-':6);
  writeln(f);
  writeln(f);
 end;
 writeln(f,' Total: ',n,' duels');
 close(f);
end;

procedure CalculateWinrates;
var
 i,j,k,n:integer;
 startDate,endDate:TDateTime;
 stat:array[1..40000,1..2] of integer;
 f:text;
begin
 n:=0;
 startDate:=GetDateFromStr('1.01.2018');
 endDate:=GetDateFromStr('10.10.2018');
 fillchar(stat,sizeof(stat),0);
 for i:=0 to high(duels) do
  with duels[i] do begin
   if (date<startDate) or (date>endDate) then continue;
   if dueltype<>2 then continue;
   if (winner<>-6) and (loser<>-6) then continue;
   if winner>0 then begin // игрок выиграл
    inc(stat[winner,1]);
    inc(stat[winner,2]);
   end else // бот выиграл
    inc(stat[loser,2]);
   inc(n);
  end;
 assign(f,'reports\winrates.txt');
 rewrite(f);
 for i:=1 to high(stat) do begin
  if stat[i,2]>=30 then begin
   for j:=1 to high(players) do
    if players[j].id=i then begin
     write(f,players[j].name,';');
     break;
    end;
   writeln(f,stat[i,1],';',stat[i,2],';',round(100*stat[i,1]/stat[i,2]));
  end;
 end;
 close(f);
end;

begin
 data.dataAddLogMsg:=DataAddLogMsg;
end.
