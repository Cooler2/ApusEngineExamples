unit ranking;
interface
 uses MyServis;

type
  // Compatibility
  StringArr=AStringArr;

  // Кэшированная информация об игроке
  TPlayerRec=record
   id:integer;
   name,guild:string[31];
   avatar,gold,crystals:integer;
   email,realname,location:AnsiString;
   customFame,customLevel,customWins,customLoses,customPlace:integer;
   classicFame,classicLevel,classicWins,classicLoses,classicPlace:integer;
   draftFame,draftLevel,draftWins,draftLoses,draftPlace:integer;
   totalFame,totalLevel,place:integer;
   campaignWins,ownedCards,astralPower:integer;
  end;
  TPlayerArr=array of TPlayerRec;

  // Информация о гильдиях
  TGuildRec=record
   name:string[31];
   size,level,mCount:shortint;
   exp,treasures,leader,place:integer;
   members:array[1..12] of integer;
  end;
  TGuildArr=array of TGuildRec;

  // Game types
  TDuelType=(
    dtNone     = 0, // also used for "Total" level/fame/rank etc...
    dtCustom   = 1,
    dtClassic  = 2,
    dtDraft    = 3,
    dtCampaign = 4);

var
  allPlayers:array of TPlayerRec;
  allGuilds:array of TGuildRec;
//  allPlayersHash:THash; // (lowercase) playername -> playerID

  // Индексы в массиве allPlayers (хранятся только игроки с ненулевой славой)
  customRanking,classicRanking,draftRanking,totalRanking:IntArray;
  // Индексы в массиве allGuilds [место]->guildID
  guildRanking:IntArray;
  rankingTime:TDateTime;

 function FormatRankingTable(dt:TDuelType;players:TPlayerArr;hlName:AnsiString):AnsiString;
 function FormatGuildsRankingTable(guilds:TGuildArr;hlName:AnsiString):AnsiString;
 
 // pages - ссылки на страницы рейтинга
 function GetRanking(dt:TDuelType;start,count:integer;out pages:AnsiString):TPlayerArr;
 function GetGuildRanking(start,count:integer;out pages:AnsiString):TGuildArr;

 function FindPlayer(name:AnsiString):integer;
 function FindGuild(name:AnsiString):integer;
 function GetPlayerInfo(id:integer):TPlayerRec;
 procedure LoadAllPlayersAndGuilds(loadGuilds:boolean=false);

implementation
 uses SysUtils,SCGI,UCalculating,Logging,NetCommon,structs;
 var
  cSect:TMyCriticalSection; // ranking protection

 type
  TRankingFunc=function(playerID:integer):int64;

 function GuildRate(guildID:integer):int64;
  begin
   with allGuilds[guildID] do
    result:=int64(level)*1000000000+exp*20+mCount;
  end;

 procedure BuildGuildRanking;
  var
   i,count:integer;
  procedure QuickSort(a,b:integer;func:TRankingFunc);
   var
    lo,hi,v,mid:integer;
    o:integer;
    midVal:int64;
   begin
    lo:=a; hi:=b;
    mid:=(a+b) div 2;
    midVal:=func(guildranking[mid]);
    repeat
     while midVal<func(guildranking[lo]) do inc(lo);
     while midVal>func(guildranking[hi]) do dec(hi);
     if lo<=hi then begin
      Swap(guildranking[lo],guildranking[hi]);
      inc(lo);
      dec(hi);
     end;
    until lo>hi;
    if hi>a then QuickSort(a,hi,func);
    if lo<b then QuickSort(lo,b,func);
   end;
  begin
   try
    SetLength(guildRanking,length(allGuilds));
    count:=0;
    for i:=1 to high(allGuilds) do
     if (allGuilds[i].name<>'') and (allGuilds[i].leader>0) then begin
      inc(count);
      guildRanking[count]:=i;
     end;
    SetLength(guildRanking,count+1);
    if count>1 then
     QuickSort(1,count,GuildRate);
    for i:=1 to high(allGuilds) do
     allGuilds[i].place:=0;
    for i:=1 to high(guildRanking) do
     allGuilds[guildRanking[i]].place:=i;
   except
    on e:exception do LogMsg('Error in BuildGuildRanking',logWarn);
   end;
  end;


 function CustomRate(playerID:integer):int64;
  begin
   with allPlayers[playerID] do
    result:=//int64(customLevel) shl 56+
       int64(customFame) shl 40+
       int64(round(1000*(customWins+10)/(customLoses+10))) shl 20+
       playerID and $FFFFF;
  end;
 function ClassicRate(playerID:integer):int64;
  begin
   with allPlayers[playerID] do
    result:=//int64(classicLevel) shl 56+
       int64(classicFame) shl 40+
       int64(round(10000*(classicWins+10)/(classicLoses+10))) shl 20+
       playerID and $FFFFF;
  end;
 function DraftRate(playerID:integer):int64;
  begin
   with allPlayers[playerID] do
    result:=//int64(draftLevel) shl 56+
       int64(draftFame) shl 40+
       int64(round(10000*(draftWins+10)/(draftLoses+10))) shl 20+
       playerID and $FFFFF;
  end;
 function TotalRate(playerID:integer):int64;
  begin
   with allPlayers[playerID] do
    result:=//int64(totalLevel) shl 56+
      int64(totalFame) shl 40+
      int64(round(1000*(classicWins+customWins+DraftWins+10)/(classicLoses+customLoses+draftLoses+10))) shl 20+
      playerID and $FFFFF;
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
  

 procedure LoadAllPlayersAndGuilds(loadGuilds:boolean=false);
  var
   sa,sb,sc:StringArr;
   i,id,cs,count,gCount,mCount,gId,plrId:integer;
  begin
   if Now<rankingTime+15/86400 then exit; // 15 seconds
   LogMsg('Ranking obsolete: '+FormatDateTime('hh:nn:ss.zzz',Now)+' > '+FormatDateTime('hh:nn:ss.zzz',rankingTime+10/86400),logDebug);
   try
    // Загрузка информации обо всех игроках
    LogMsg('Updating players info',logInfo);
    sa:=db.Query('SELECT max(id) FROM players');
    count:=StrToIntDef(sa[0],0)+1;
    if db.rowCount>0 then begin // не было ошибки?

     sa:=db.Query('SELECT id,name,guild,email,customFame,customLevel,classicFame,classicLevel,draftFame,draftLevel,level,'+
       'customWins,customLoses,classicWins,classicLoses,draftWins,draftLoses,'+
       'realname,location,campaignWins,cards,astralPower,avatar,gold,gems FROM players WHERE modified>"'+
         FormatDateTime('yyyy-mm-dd hh:nn:ss',rankingTime-3/86400)+'"');

     cSect.Enter;
     try
     SetLength(allPlayers,count);
     if db.rowCount>0 then begin
      for i:=0 to db.rowCount-1 do begin
       cs:=db.colCount;
       id:=StrToInt(sa[i*cs]);
       if (id>0) and (id<length(allPlayers)) then begin
        allPlayers[id].id:=id;
        allPlayers[id].name:=sa[i*cs+1];
        allPlayers[id].guild:=sa[i*cs+2];
        allPlayers[id].email:=sa[i*cs+3];
        allPlayers[id].customFame:=StrToInt(sa[i*cs+4]);
        allPlayers[id].customLevel:=StrToInt(sa[i*cs+5]);
        allPlayers[id].classicFame:=StrToInt(sa[i*cs+6]);
        allPlayers[id].classicLevel:=StrToInt(sa[i*cs+7]);
        allPlayers[id].draftFame:=StrToInt(sa[i*cs+8]);
        allPlayers[id].draftLevel:=StrToInt(sa[i*cs+9]);
        allPlayers[id].totalFame:=CalcPlayerFame(allPlayers[id].customFame,allPlayers[id].classicFame,allPlayers[id].draftFame);
        allPlayers[id].totalLevel:=StrToInt(sa[i*cs+10]);
        allPlayers[id].customWins:=StrToInt(sa[i*cs+11]);
        allPlayers[id].customloses:=StrToInt(sa[i*cs+12]);
        allPlayers[id].classicWins:=StrToInt(sa[i*cs+13]);
        allPlayers[id].classicLoses:=StrToInt(sa[i*cs+14]);
        allPlayers[id].draftWins:=StrToInt(sa[i*cs+15]);
        allPlayers[id].draftLoses:=StrToInt(sa[i*cs+16]);
        allPlayers[id].realname:=sa[i*cs+17];
        allPlayers[id].location:=sa[i*cs+18];
        allPlayers[id].campaignWins:=StrToInt(sa[i*cs+19]);
        allPlayers[id].ownedCards:=CardsCount(sa[i*cs+20]);
        allPlayers[id].astralPower:=StrToInt(sa[i*cs+21]);
        allPlayers[id].avatar:=StrToInt(sa[i*cs+22]);
        allPlayers[id].gold:=StrToInt(sa[i*cs+23]);
        allPlayers[id].crystals:=StrToInt(sa[i*cs+24]);
       end;
      end;
      LogMsg('Players loaded: '+inttostr(db.rowCount),logInfo);
      BuildRanking(dtCustom);
      BuildRanking(dtClassic);
      BuildRanking(dtDraft);
      BuildRanking(dtNone);
      LogMsg('Rankings built',logDebug);
     end; // Data loaded
     finally
      cSect.Leave;
     end;
    end;

    if loadGuilds then begin
     sb:=db.Query('SELECT id,name,size,exp,level,treasures FROM guilds WHERE flags=0');
     gCount:=db.rowCount;
     sc:=db.Query('SELECT guild,playerid,rank FROM guildmembers WHERE guild>0');
     mCount:=db.rowCount;
     cSect.Enter;
     try
      LogMsg('Loading guilds',logInfo);
      SetLength(allGuilds,0);
      for i:=0 to gCount-1 do begin
       id:=StrToInt(sb[i*6]);
       if id>high(allGuilds) then SetLength(allGuilds,id+500);
       allGuilds[id].name:=sb[i*6+1];
       allGuilds[id].size:=StrToInt(sb[i*6+2]);
       allGuilds[id].exp:=StrToInt(sb[i*6+3]);
       allGuilds[id].level:=StrToInt(sb[i*6+4]);
       allGuilds[id].treasures:=StrToInt(sb[i*6+5]);
       allGuilds[id].leader:=0;
       allGuilds[id].mCount:=0;
       fillchar(allGuilds[id].members,sizeof(allGuilds[id].members),0);
      end;
      for i:=0 to mCount-1 do begin
       gId:=StrToInt(sc[i*3]);
       if (gId>0) and (gId<=high(allGuilds)) then begin
        plrId:=StrToInt(sc[i*3+1]);
        inc(allGuilds[gId].mCount);
        if allGuilds[gId].mCount<=12 then
         allGuilds[gId].members[allGuilds[gId].mCount]:=plrId
        else
         LogMsg('Too many guild members! guildID='+inttostr(gId)+' plrID='+inttostr(plrID),logInfo);
        if sc[i*3+2]='3' then
         allGuilds[gId].leader:=plrId;
       end;
      end;
      LogMsg('Guilds loaded: '+inttostr(db.rowCount),logInfo);
      BuildGuildRanking;
      LogMsg('Ranking built',logDebug);
     finally
      cSect.Leave;
     end;
    end;
   except
    on e:exception do LogMsg('Error: LoadAllPlayers - '+ExceptionMsg(e),logError);
   end;
   rankingTime:=now;
  end;

 function FormatGuildsRankingTable(guilds:TGuildArr;hlName:AnsiString):AnsiString;
  var
   i,id:integer;
   place,level,exp,loses:integer;
   name,leader,bold:AnsiString;
  begin
   result:='';
   for i:=0 to high(guilds) do begin
    place:=guilds[i].place;
    level:=guilds[i].level;
    exp:=guilds[i].exp;
    leader:='unknown';
    id:=guilds[i].leader;
    if (id>0) and (id<=high(allPlayers)) then leader:=HTMLString(allPlayers[id].name); 

    if place=0 then bold:=' style="font-weight:bold"' else bold:='';
    if hlName=guilds[i].name then bold:=' style="font-weight:bold; color:#407;"';
    name:=HTMLString(guilds[i].name);
    result:=result+Format('<tr%s><td>%d.<td class=GuildInfo>%s<td>%d<td>%d<td>%s'#13#10,
     [bold,place,name,level,exp,leader]);
   end;
  end;

 function FormatRankingTable(dt:TDuelType;players:TPlayerArr;hlName:AnsiString):AnsiString;
  var
   i:integer;
   place,level,fame,wins,loses:integer;
   name,bold:AnsiString;
  begin
   result:='';
   for i:=0 to high(players) do begin
    case dt of
     dtNone:begin
       place:=players[i].place;
       fame:=players[i].totalFame;
       level:=CalcLevel(fame);
       wins:=players[i].customWins+players[i].classicWins+players[i].draftWins;
       loses:=players[i].customLoses+players[i].classicLoses+players[i].draftLoses;
     end;
     dtCustom:begin
       place:=players[i].customPlace;
       fame:=players[i].customFame;
       level:=CalcLevel(fame);
       wins:=players[i].customWins;
       loses:=players[i].customLoses;
     end;
     dtClassic:begin
       place:=players[i].classicPlace;
       fame:=players[i].classicFame;
       level:=CalcLevel(fame);
       wins:=players[i].classicWins;
       loses:=players[i].classicLoses;
     end;
     dtDraft:begin
       place:=players[i].draftPlace;
       fame:=players[i].draftFame;
       level:=CalcLevel(fame);
       wins:=players[i].draftWins;
       loses:=players[i].draftLoses;
     end;
    end;
    if (place=1) then bold:=' style="font-weight:bold"' else bold:='';
    if hlName=players[i].name then bold:=' style="font-weight:bold; color:#407;"';
    name:=HTMLString(players[i].name);
    result:=result+Format('<tr%s><td>%d.<td class=PlayerInfo>%s<td>%d<td>%d<td>%d / %d'#13#10,
     [bold,place,name,level,fame,wins,loses]);
   end;
  end;

 function GetRanking(dt:TDuelType;start,count:integer;out pages:AnsiString):TPlayerArr;
  var
   i,c,place,pCount,page,duels:integer;
   ranking:^IntArray;
   st:AnsiString;
  begin
   LoadAllPlayersAndGuilds(true);
   cSect.Enter;
   try
    case dt of
     dtNone:ranking:=@totalRanking;
     dtCustom:ranking:=@customRanking;
     dtClassic:ranking:=@ClassicRanking;
     dtDraft:ranking:=@DraftRanking;
    end;
    SetLength(result,count);
    // посчитаем сколько страниц вообще в рейтинге есть
    pCount:=1;
    while pCount*100<=high(ranking^) do begin
     with allPlayers[ranking^[pCount*100]] do
      case dt of
       dtCustom:duels:=customWins+customLoses;
       dtClassic:duels:=classicWins+classicLoses;
       dtDraft:duels:=draftWins+draftLoses;
       dtNone:duels:=customWins+customLoses+classicWins+classicLoses+draftWins+draftLoses;
      end;
     if duels<=0 then break; 
     inc(pCount);
    end;
    place:=start;
    c:=0;
    while (c<count) and (place<high(ranking^)) do begin
     result[c]:=allPlayers[ranking^[place]];
     inc(c); inc(place);
    end;
    SetLength(result,c);
   finally
    cSect.Leave;
   end;

   pages:='';
   page:=1+start div 100;
   for i:=1 to pCount do begin
    if pCount>8 then begin
     // страниц больше 8 - тогда 2 варианта:
     if (page<=6) and (i>8) then break; // текущая страница - до 4-й, значит рисуем до 6-й включительно
     if (page>6) and (i>1) and (abs(i-page)>3) then begin // показывать 1-ю страницу а также +/- 3 от текущей
      continue;
     end;
    end;
    st:='';
    if i=page then st:=' RankingPageCurrent';
    pages:=pages+'<span id=RankingPage'+inttostr(ord(dt))+'_'+inttostr(i)+' class="RankingPageIndex'+st+'">'+inttostr(i)+'</span>';
   end;
  end;

 function GetGuildRanking(start,count:integer;out pages:AnsiString):TGuildArr;
  var
   i,c,place,pCount,page,duels:integer;
   ranking:^IntArray;
   st:AnsiString;
  begin
   LoadAllPlayersAndGuilds(true);
   cSect.Enter;
   try
    SetLength(result,count);
    // посчитаем сколько страниц вообще в рейтинге есть
    pCount:=(length(guildRanking)-2) div 100;
    place:=start;
    c:=0;
    while (c<count) and (place<high(guildRanking)) do begin
     result[c]:=allGuilds[guildRanking[place]];
     inc(c); inc(place);
    end;
    SetLength(result,c);
   finally
    cSect.Leave;
   end;

   pages:='';
   page:=1+start div 100;
   for i:=1 to pCount do begin
    if pCount>8 then begin
     // страниц больше 8 - тогда 2 варианта:
     if (page<=6) and (i>8) then break; // текущая страница - до 4-й, значит рисуем до 6-й включительно
     if (page>6) and (i>1) and (abs(i-page)>2) then begin // показывать 1-ю страницу а также +/- 2 от текущей
      if i=1 then pages:=pages+' .. ';
      continue;
     end;
    end;
    st:='';
    if i=page then st:=' RankingPageCurrent';
    pages:=pages+'<span id=RankingPage4_'+inttostr(i)+' class="RankingPageIndex'+st+'">'+inttostr(i)+'</span>';
   end;
  end;


 function FindPlayer(name:AnsiString):integer;
  var
   i:integer;
  begin
   result:=0;
   name:=lowercase(name);
   LoadAllPlayersAndGuilds;
   cSect.Enter;
   try
    for i:=1 to high(allPlayers) do
     if lowercase(allPlayers[i].name)=name then begin
      result:=i; break;
     end;
    LogMsg('Player '+name+' not found in AllPlayers');
   finally
    cSect.Leave;
   end;
  end;

 function FindGuild(name:AnsiString):integer;
  var
   i:integer;
  begin
   result:=0;
   name:=lowercase(name);
   LoadAllPlayersAndGuilds(true);
   cSect.Enter;
   try
    for i:=1 to high(allGuilds) do
     if lowercase(allGuilds[i].name)=name then begin
      result:=i; break;
     end;
    LogMsg('Guild '+name+' not found in AllGuilds');
   finally
    cSect.Leave;
   end;
  end;

 function GetPlayerInfo(id:integer):TPlayerRec;
  begin
   LoadAllPlayersAndGuilds;
   cSect.Enter;
   try
    fillchar(result,sizeof(result),0);
    if (id>0) and (id<=high(allPlayers)) then result:=allPlayers[id];
   finally
    cSect.Leave;
   end;
  end;

initialization
 InitCritSect(cSect,'ranking');  
end.
