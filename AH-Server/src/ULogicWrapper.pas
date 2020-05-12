unit ULogicWrapper;

interface
uses MyServis,ULogic;

var
 logStr:string;
 turnChanged:boolean; // Устанавливается ТОЛЬКО в CheckDuelMsg

threadvar serverThreadNum:integer; // Это номер gamelogic, используемый в текущем потоке (1..N, 0 - используется только в сетевом)

// Сервер вызывает функцию каждый раз, когда кто-то из дуэлянтов
// шлет дуэльный пакет, т.е. пакет начинающийся на нолик.
// Функция возвращает:
// 0, если ничё особого не произошло и дуэль продолжается
// 1, если приславший эту мессагу игрок считерил. Таймаут ему за это!
// 2, если приславший эту мессагу игрок выиграл
// 3, если приславший эту мессагу игрок проиграл
// 4, если игрок не имел права присылать такую мессагу, ибо не его сейчас ход - просто игнорить с записью в лог
// -1, если приславший эту мессагу незареген, а пытается кастать особое
// -2, если наверно рассинхронизация при создании дуэли.
function CheckDuelMsg(userID:integer;var DuelSave:tDuelSave;curTurn:integer;buf:array of integer):integer;

// Вызывать тогда, когда ход бота (т.е. от бота ожидается какое-либо действие)
// Возвращает массив значений, как если бы они были получены от клиента-бота по сети
// Необходимо чтобы serverThreadNum содержал уникальный номер потока (1..n)
function MakeAiDecisions(var DuelSave:tDuelSave):AStringArr;

// Проводит бой между двумя AI-ботами, возвращает индекс победителя (1 или 2)
function MakeAIduel(dueltype:integer;var plr1,plr2:tplayerInfo):integer;

implementation
uses {cnsts,}sysutils,UOutput,ucompai,ServerLogic,logging;


function MakeAiDecisions(var DuelSave:tDuelSave):AStringArr;
 var aiaction:tAIAction;
     values:AStringArr;
 begin
  fillchar(aiaction,sizeof(aiAction),0);
  try
  duelsave.ExportData(serverThreadNum);
  FindBestAction(aiaction,serverThreadNum);
  setlength(values,5);
  values[0]:='0';
  values[1]:=inttostr(aiaction.ActionType);
  values[2]:=inttostr(aiaction.ActionDesc);
  values[3]:=inttostr(aiaction.ActionTarget);
  if aiaction.ActionType=1 then begin
   ASSERT(duelsave.saveduel.curplayer in [1..2],'WARN! BAD curplayer!');
   ASSERT(aiaction.ActionDesc in [1..8],'WARN! BAD actionDesc!');
   values[4]:=inttostr(duelsave.saveduel.players[duelsave.saveduel.curplayer].handcards[aiaction.ActionDesc])
  end else
   values[4]:='0';
  except
   on e:Exception do begin
    LogMsg('Error in MakeAIDecision: '+ExceptionMsg(e),logWarn);
    with aiAction do
     LogMsg('Action: %d %d %d %d %d',[ActionType,ActionDesc,ActionTarget,DescCard,ActionResult],logNormal);
   end;
  end;
  result:=values;
 end;


function CheckDuelMsg(userID:integer;var DuelSave:tDuelSave;curTurn:integer;buf:array of integer):integer;
var q,w,e,r,t,n,el,num,card,size:integer;
    s:UTF8String;
    oldPl:integer;
begin
 duelsave.ExportData(serverThreadNum);
 size:=length(buf);
 logStr:='Thread:'+IntToStr(serverThreadNum)+' Msg from '+users[userID].name+':';
 w:=4;
 if size-1<w then w:=size-1;
 for q:=0 to w do logStr:=logStr+' '+inttostr(buf[q]);
 logstr:=logstr+#13#10;
 result:=0;
 if buf[0]=0 then
 with duelsave.SaveDuel do
 begin
   oldPl:=curplayer;
   if curplayer<>curTurn then begin
    // Пакет не от того игрока, чей сейчас ход
    if buf[1]<>5 then begin
     result:=4; exit;
    end;
   end;
   s:=Format(' Curplr: %d  Life: %d  Mana: %d/%d ',
      [curplayer,players[curplayer].life,players[curplayer].mana,players[curplayer].spellpower]);
   s:=s+'Hash is: '+IntToStr(gamelogic[serverThreadNum].duel.getPlayerHash(oldpl));
   s:=s+' Cards: ';
   for q:=1 to players[curplayer].numhandcards do begin
     s:=s+inttostr(players[curplayer].handcards[q])+' ';
   end;
   logStr:=logStr+s+'  ';
   s:=#13#10': ';
   for q:=1 to 6 do
    with players[curplayer].creatures[q] do
     s:=s+inttostr(cardnum)+':'+inttostr(life)+' ';
   s:=s+#13#10': ';
   for q:=1 to 6 do
    with players[3-curplayer].creatures[q] do
     s:=s+inttostr(cardnum)+':'+inttostr(life)+' ';
   logStr:=logStr+s;
{  if turnnumber=0 then
   inc(turnnumber);}
  n:=Curplayer;
  case buf[1] of
   0:begin
      logStr:=logStr+'End turn';
//       forcelogmessage('End turn');
      EndTurn;
     end;
   1:begin
//       forcelogmessage('UseCard');
      logStr:=logStr+'UseCard';
      num:=buf[2];
      t:=shortint(buf[3]);  // цель
      card:=buf[4];
      if players[curplayer].handcards[num]<>card then begin
       result:=-2;
      end else
      if canusecard(num) then
      begin
       if (card=76)or(cantargetcard(num,t)) then
        UseCard(num,t)
       else
        result:=1
      end else
       result:=1;
     end;
   2:begin
      logStr:=logStr+'UseAbilityCard';
      num:=buf[2];
      t:=shortint(buf[3]);  // цель
      if canuseability(num) then
      begin
       if (card=7)or(cantargetability(num,t)) then
        UseAbility(num,t)
       else
        result:=1
      end else
       result:=1;
     end;
   3:begin
{      logStr:=logStr+'SacrificeCard';
      num:=buf[2];
      if cansacrificecard(num) then
       sacrificecard(num)
      else
       result:=1}
     end;
   4:begin
      logStr:=logStr+'ReplaceCard';
      num:=buf[2];
      if wasreplace=false then
       replacecard(num)
      else
       result:=1
     end;
   5:begin
//       forcelogmessage('Surrender');
       logStr:=logStr+'Surrender';
       result:=3;
       exit;
      end;
  end;
  if result<>1 then
  begin
   if winner=n then
    result:=2
   else if winner=3-n then
    result:=3;
  end;
  turnChanged:=(oldPl<>curplayer);
 end;
 logStr:=logStr+' Res='+inttostr(result);
 duelsave.SavePlayersInfo[1].CurDeck.Cards:=gamelogic[serverThreadNum].playersinfo[1].CurDeck.Cards;
 duelsave.SavePlayersInfo[2].CurDeck.Cards:=gamelogic[serverThreadNum].playersinfo[2].CurDeck.Cards;
// forcelogmessage('Result='+inttostr(result));
end;

function MakeAIduel(dueltype:integer;var plr1,plr2:tplayerInfo):integer;
var
 q:integer;
begin
 result:=0;
 with gamelogic[serverThreadNum] do begin
   plr1.time:=0;
   plr2.time:=0;
   playersinfo[1]:=plr1;
   playersinfo[2]:=plr2;

   for q:=1 to 2 do
    playersinfo[q].Deck.Prepare;
   duel.PrepareDuel(dueltype,'',serverThreadNum);

   while duel.winner=0 do begin
    repeat
     duel.CurEff:=0;
     aiinfo.combating:=true;
     aiinfo.thinking:=false;
     aiinfo.aiplayer:=Duel.curplayer;
     sleep(0);
     FindBestAction(AIAction,serverThreadNum);
     if duel.curplayer in [1..2] then
      inc(playersinfo[duel.curplayer].time,7);
     with duel do
     case AiAction.ActionType of
      1:UseCard(AiAction.ActionDesc,AiAction.ActionTarget);
      2:UseAbility(AiAction.ActionDesc,AiAction.ActionTarget);
      4:Replacecard(AiAction.ActionDesc);
     end;
    until (AIAction.ActionType=0)or(duel.winner>0);
    if duel.winner=0 then
     duel.endTurn;
   end;
   plr1.time:=playersinfo[1].time;
   plr2.time:=playersinfo[2].time;
   result:=duel.winner;
 end;
end;

initialization
// PairPowerLoad;
end.
