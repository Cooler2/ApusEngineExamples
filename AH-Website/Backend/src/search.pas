unit search;
interface

 // Производит поиск (везде) и формирует HTML-код кратких результатов поиска (не более count шт) 
 function RunSearch(query:AnsiString;count:integer):AnsiString;

 // Загрузка и индексация полного содержимого форума
 // Пока что индексация изменений на лету не проводится, вместо этого периодически индексируется весь форум
 procedure IndexAllForum;

 // Сообщение о том, что на форуме что-то изменилось.
 // при достижении 100 - немедленная переиндексация
 procedure ForumChanged(rate:integer);

implementation
 uses SysUtils,MyServis,TextUtils,structs,logging,SCGI,ranking,forum;

 type
  TForumTopic=record
   title:WideString;
   chapter,msgCount:integer;
   created,updated:TDateTime;
   rating:single;
   lang:string[2];
   flags:byte;
  end;

  TForumMessage=record
   text,lText:WideString;
   topic:integer;
   created:TDateTime;
   authorID:integer;
   authorName:AnsiString;
   score:integer;
  end;

  TWord=record
   word:WideString; // lowercase
   msglist:IntArray; // список ID сообщений, в которых данное слово встречается
   ignore:boolean;
  end;

 var
  cSect:TMyCriticalSection;

  topics:array of TForumTopic; // [id]
  messages:array of TForumMessage; // [id]
  words:array of TWord;
  wordHash:THash; // слово -> индекс в words
  ignoreWords:THash; // эти слова слишком частые - их нужно игнорить

  changes:integer;
  lastIndexed:TDateTime;



 procedure ForumChanged(rate:integer);
  begin
   inc(changes,rate);
   // Переиндексировать раз в час минут или если накопилось много изменений
   if (changes>=100) or (Now>lastIndexed+60/1440) then AddTask('/IndexForum');
  end;

 // Возвращает список ID сообщений, более-менее соответствующих запросу
 function FindForumMessages(query:WStringArr):IntArray;
  var
   i,j,k,d,l,lw,lq,n,penalty:integer;
   rates:IntArray;
   rate,maxrate:integer;
   ia:IntArray;
  begin
   SetLength(result,0);
   SetLength(rates,length(messages));
   // Пройдёмся по всем словам, дадим им оценку и выберем сообщения, в которых они присутствуют
   for i:=0 to high(words) do begin
    if words[i].ignore then continue;
    for j:=0 to high(query) do begin
     if length(query[j])<2 then continue;
     // насколько слово соответствует слову запроса
     ia:=GetMaxSubsequence(query[j],words[i].word);

     penalty:=0;
     l:=length(ia)+1;
     if l>3 then
      for k:=2 to high(ia) do
       inc(penalty,ia[k]-ia[k-1]-1);

     lq:=length(query[j])+1+penalty;
     lw:=length(words[i].word)+1+penalty;
     rate:=round(100*(l/lq)*(l/lw));
     if rate>60 then begin
      for k:=0 to high(words[i].msglist) do
       inc(rates[words[i].msglist[k]],rate-50);
     end;
    end;
   end;

   rate:=0; n:=0; maxrate:=0;
   for i:=1 to high(rates) do
    if rates[i]>0 then begin
     inc(n);
     inc(rate,sqr(rates[i]));
     if rates[i]>maxRate then maxrate:=rates[i];
    end;
   if n=0 then exit;
   rate:=round(0.8*sqrt(rate/n));

   // Корректировка порога если результатов сликом много/мало
   n:=0;
   for i:=1 to high(rates) do
    if rates[i]>rate then
     inc(n);
   // так делать нельзя: если много результатов с примерно одинаковой оценкой, то при увеличени оценки они ВСЕ! отсекаются
   //if n>100 then rate:=round(rate*1.3);
   if n>100 then rate:=round(rate*0.6+maxRate*0.4);
   if n<10 then rate:=round(rate*0.8);

   for i:=1 to high(rates) do
    if rates[i]>rate then
     AddInteger(result,i);
  end;

 // Оценивает сообщение и формирует вырезку из него, наиболее близкую к запросу
 function RateForumMessage(query:WStringArr;msgText,title,author:WideString;out quote:WideString;explain:boolean=false):single;
  var
   i,j,k,d,l,best,bestS,bestE:integer;
   txt:WStringArr;
   rate:single;
   ia:IntArray;
   hl:array of byte;
   exp:AnsiString;
  begin
   result:=0; exp:='';
   SetLength(hl,length(msgText)+1);
   txt:=SplitToWords(WideLowerCase(msgText+' '+title+' '+author));
   SortStrings(txt);
   for i:=0 to high(query) do
    for j:=0 to high(txt) do begin
     // Слова неподходящей длины?
     l:=length(txt[j]);
     if (l<2) or (l>40) then continue;
     l:=length(query[i]);
     if (l<2) or (l>30) then continue;

     // повторяющееся слово?
     if (j>0) and (txt[j]=txt[j-1]) then begin
      rate:=rate/3.5;
      result:=result+rate;
      if explain and (rate>0.01) then exp:=exp+Format('  [rep:%s] +%.2f ->%.2f;'#13#10,[txt[j],rate,result]);
      continue;
     end;
     // слово еще не встречалось
     d:=GetWordsDistance(query[i],txt[j]);
     if (length(query[i])>4) and (d>1) then dec(d);

     ia:=GetMaxSubsequence(query[i],txt[j]);
     l:=length(ia)+1;
     rate:=10*(l/(1+length(query[i]))) * (l/(1+length(txt[j])))-4;
     if rate<1 then rate:=0;
     if d<length(query[i]) div 3 then
      rate:=rate+10/(1+d);

     result:=result+rate;
     if explain and (rate>0) then
      exp:=exp+Format('  [%s]~[%s] +%.2f ->%.2f'#13#10,[query[i],txt[j],rate,result]);

     if rate>4 then begin
      // Отметим места в тексте, где данное слово присутствует
      l:=1;
      repeat
       d:=PosFrom(txt[j],msgtext,l,true);
       if d<=0 then break;
       l:=d+1;
       inc(hl[d],round(rate));
      until false;
     end;
    end;

   l:=length(msgtext);
   if l<200 then result:=result*(1.05-11/(l+10));

   if explain then LogMsg(#13#10+exp,logInfo);

   quote:=msgText;
   if length(quote)<=250 then exit;
   // Выделить цитату длиной не более 250 символов
   i:=1; j:=220;
   // Поиск и оценка начальной цитаты
   while (j>i+1) and (quote[j]<>' ') do dec(j);
   d:=0;
   for k:=i to j-1 do inc(d,hl[k]);
   // теперь будем скользить пока не найдём наилучший вариант
   best:=d; bestS:=i; bestE:=j;
   repeat
    // Сдвинем правую границу на 1 слово (или до конца строки)
    inc(j);
    while (j<=length(quote)) and (quote[j]<>' ') do begin
     inc(d,hl[j]); inc(j);
    end;
    // Сдвинем левую границу, чтобы длина цитаты была допустимой
    while (j-i>220) do begin
     dec(d,hl[i]); inc(i);
    end;
    // Теперь сдвинем левую границу к началу слова
    while (i>1) and (i<j-1) and (quote[i-1]<>' ') do begin
     dec(d,hl[i]); inc(i);
    end;
    // Сравним оценку и если надо - запомним
    if d>=best then begin
     best:=d;
     bestS:=i; bestE:=j;
    end;
   until j>=length(quote);
   // Попробуем отодвинуть левую границу к началу предложения
   i:=bestS;
   while (i>0) and (not (quote[i] in ['.',',','!','?'])) do dec(i);
   if bestS-i<50 then bestS:=i+1;
   quote:=copy(quote,bestS,bestE-bestS);
  end;

 // Производит поиск по форуму и форматирует результат в виде HTML
 function SearchForum(query:WStringArr;src:WideString;count:integer):AnsiString;
  var
   i,j,item,msgID,threadID:integer;
   list,order:IntArray;
   quotes:WStringArr;
   rates,rates2:array of single;
   maxrate:single;
   wst:WideString;
  begin
   cSect.Enter;
   try
    // 1. Выбрать сообщения, потенциально подходящие запросу
    list:=FindForumMessages(query);

    // 2. Оценить сообщения
    SetLength(quotes,length(list));
    SetLength(rates,length(list));
    SetLength(rates2,length(list));
    for i:=0 to high(list) do begin
     msgID:=list[i];
     threadID:=messages[msgID].topic;
     rates[i]:=RateForumMessage(query,messages[msgID].text,topics[threadID].title,
       messages[msgID].authorName,quotes[i]);
     rates2[i]:=rates[i];
     // коррекция оценки исходя из голосования
     rates[i]:=rates[i]*(1+sat(messages[msgid].score,-10,15)/30);
     // ответы админов всегда в плюсе
     if (messages[msgid].authorName='Cooler') or (messages[msgid].authorName='Estarh') then
      rates[i]:=rates[i]*1.15+1;
     // Старые сообщения менее интересны
     rates[i]:=rates[i]-0.5*sqrt(Now-messages[msgid].created);
    end;

    // 3. Отсортировать по оценке
    SetLength(order,length(list));
    for i:=0 to high(list) do order[i]:=i;
    for i:=0 to high(list)-1 do
     for j:=i+1 to high(list) do
      if rates[order[j]]>rates[order[i]] then Swap(order[j],order[i]);

    if length(order)>0 then maxrate:=rates[order[0]] else maxrate:=0;

    // Если запрос начинается с ??? - вывести в лог подробное описание оценки лучших постов
    if pos(WideString('???'),src)=1 then begin
     for i:=0 to 9 do
      if i<=high(list) then begin
       msgID:=list[order[i]];
       threadID:=messages[msgID].topic;
       LogMsg('%d. Explanation for: %s %s'#13#10'  %s',
         [i+1,messages[msgID].authorName,topics[threadID].title,messages[msgID].text],logInfo);
       RateForumMessage(query,messages[msgID].text,topics[threadID].title,
         messages[msgID].authorName,wst,true);
       LogMsg('Final rate: %.2f -> %.2f',[rates2[order[i]],rates[order[i]]],logInfo);
      end;
    end;

    // 4. Отформатировать результат
    if count>high(list) then count:=high(list)+1;

    while (count>0) and (rates[order[count-1]]<maxrate*0.5) do dec(count);
    result:='';
    for i:=0 to count-1 do begin
     item:=order[i];
     msgid:=list[item];
     threadID:=messages[msgID].topic;
     temp.Put('SEARCH_MSGID',msgid);
     temp.Put('SEARCH_MSGAUTHOR',messages[msgid].authorName);
     temp.Put('SEARCH_MSGAUTHORID',messages[msgid].authorID);
     temp.Put('SEARCH_MSGDATE',messages[msgid].created);
     temp.Put('SEARCH_AGE',round(Now-messages[msgid].created));
     temp.Put('SEARCH_MSGSCORE',FloatToStrF(rates[order[i]],ffFixed,5,2)+'/'+FloatToStrF(rates2[order[i]],ffFixed,5,2));
     temp.Put('SEARCH_THREADID',threadID);
     temp.Put('SEARCH_THREADNAME',EncodeUTF8(topics[threadID].title));
     temp.Put('SEARCH_MSG_QUOTE',EncodeUTF8(quotes[item]));
     temp.Put('SEARCH_CHAPTER',topics[threadID].chapter);
     temp.Put('SEARCH_CHAPTER_URL',chapterURL[topics[threadID].chapter]);
     result:=result+BuildTemplate('#SEARCH_RESULTS_FORUM_ITEM');
    end;
    if count<=0 then result:=BuildTemplate('$SEARCH_NOTHING_FOUND');
   finally
    cSect.Leave;
   end;
  end;

 function RunSearch(query:AnsiString;count:integer):AnsiString;
  var
   words:WStringArr;
   qw:WideString;
   res:AnsiString;
   t:int64;
  begin
   t:=MyTickCOunt;
   qw:=DecodeUTF8(query);
   qw:=WideLowerCase(qw);
   words:=SplitToWords(qw);
   res:=SearchForum(words,qw,count);
   temp.Put('SEARCH_RESULTS_FORUM',res,true);
   t:=MyTickCount-t;
   temp.Put('SEARCH_TIME',t,true);
   LogMsg('Search query (%d ms): %s',[t,query]);
   result:=BuildTemplate('#SEARCH_RESULTS_SHORT');
  end;

 procedure IndexForumData;
  var
   i,j,k,wIdx:integer;
   st:WideString;
   sa:WStringArr;
   us:AnsiString;
   maxUse,maxLength,longestIdx:integer;
  begin
   maxLength:=0; maxuse:=0; longestIdx:=-1;
   LogMsg('Building words list');
   cSect.Enter;
   try
    // Составляем глобальный список слов и указателей на сообщения, в которых они встречаются
    ignoreWords.Init(false);
    wordHash.Init(false);
    SetLength(words,0);
    for i:=1 to high(messages) do begin
     if messages[i].topic=0 then continue;
     // Надо будет еще учитывать веса слов и добавлять слова из названия темы и имя автора
     st:=WideLowerCase(messages[i].text+' '+topics[messages[i].topic].title+' '+DecodeUTF8(messages[i].authorName));
     sa:=SplitToWords(st);
     try
      SortStrings(sa);
     except
      on e:exception do
       LogMsg('ERR'+inttostr(i));
     end;
     for j:=0 to high(sa) do begin
      if (j>0) and (sa[j]=sa[j-1]) then continue; // слово уже было
      k:=length(sa[j]);
      if (k<2) or (k>40) then continue; // Слишком длинные или короткие слова
      us:=EncodeUTF8(sa[j]);
      if not wordHash.HasKey(us) then begin
       wIdx:=length(words);
       wordHash.Put(us,wIdx);
       SetLength(words,wIdx+1);
       words[wIdx].word:=sa[j];
       words[wIdx].ignore:=false;
       SetLength(words[wIdx].msglist,0);
       if length(sa[j])>maxLength then begin
        maxLength:=length(sa[j]);
        longestIdx:=wIdx;
       end;
      end else
       wIdx:=wordHash.Get(us);
      AddInteger(words[wIdx].msglist,i);
      maxuse:=max2(maxUse,length(words[wIdx].msglist));
     end;
    end;
    // Слишком частые слова - в игнор-лист
    LogMsg('Optimizing words');
    j:=max2(50,high(messages) div 8);
    for i:=0 to high(words) do begin
     if length(words[i].msglist)>j then begin
      ignoreWords.Put(EncodeUtf8(words[i].word),true);
      words[i].ignore:=true;
     end;
     // редкое слово - опечатка?
//     if length(words[i].msglist)<3 then
    end;
   finally
    cSect.Leave;
   end;
   LogMsg('Forum data indexed');
  end;

 procedure RemoveQuotes(var st:AnsiString);
  var
   i,j:integer;
  begin
   repeat
    i:=PosFrom('<div class="QuoteAuthor"',st,1,true);
    j:=PosFrom('/div>',st,i+25,true);
    if (i>0) and (j>0) then
     delete(st,i,j-i+5);
   until i=0;

   repeat
    i:=PosFrom('<blockquote',st,1,true);
    j:=PosFrom('/blockquote>',st,i+10,true);
    if (i>0) and (j>0) then
     delete(st,i,j-i+12);
   until i=0;
  end;

 procedure IndexAllForum;
  var
   i,n,id,topic:integer;
   sa:StringArr;
   date:TDateTime;
   txt:AnsiString;
  begin
   if Now<lastIndexed+5/1440 then exit; // Слишком часто! Не запускать чаще чем раз в 5 минут
   changes:=0;
   lastIndexed:=Now;
   LogMsg('Loading all forum data');
   // Загрузка всех тем форума, кроме скрытых, удалённых и гильдейских
   sa:=db.Query('SELECT id,title,chapter,lang,flags FROM topics WHERE flags&10=0 AND guild=0 ORDER BY id DESC');
   if db.lastErrorCode=0 then begin
    cSect.Enter;
    try
     SetLength(topics,0);
     for i:=0 to db.rowCount-1 do begin
      n:=i*db.colCount;
      id:=StrToIntDef(sa[n],0);
      if id>high(topics) then SetLength(topics,id+1);
      topics[id].title:=DecodeUTF8(sa[n+1]);
      topics[id].chapter:=StrToIntDef(sa[n+2],0);
      topics[id].lang:=sa[n+3];
      topics[id].flags:=StrToIntDef(sa[n+4],0);
     end;
    finally
     cSect.Leave;
    end;
   end;
   // Загрузка всех сообщений форума (и обновление параметрв соответствующих тем
   sa:=db.Query('SELECT id,msg,topic,created,author,authorname,score FROM messages ORDER BY id DESC');
   if db.lastErrorCode=0 then begin
    cSect.Enter;
    try
     SetLength(messages,0);
     for i:=0 to db.rowCount-1 do begin
      n:=i*db.colCount;
      id:=StrToIntDef(sa[n],0);
      topic:=StrToIntDef(sa[n+2],0);
      // Проверка допустимости темы
      if (topic<0) or (topic>high(topics)) then continue;
      if topics[topic].title='' then continue;

      if id>high(messages) then SetLength(messages,id+1);
      txt:=sa[n+1];
      // удалить цитаты
      RemoveQuotes(txt);
      txt:=ExtractPlainText(txt);
      messages[id].text:=DecodeUTF8(txt);
//      messages[id].lText:=WideLowerCase(messages[id].text);
      messages[id].topic:=topic;
      messages[id].created:=GetDateFromStr(sa[n+3]);
      messages[id].authorID:=StrToIntDef(sa[n+4],0);
      messages[id].authorName:=sa[n+5];
      messages[id].score:=StrToIntDef(sa[n+6],0);
      date:=messages[id].created;
      if (topic<=0) or (topic>high(topics)) then continue;
      inc(topics[topic].msgCount);
      topics[topic].updated:=max2D(topics[topic].updated,date);
      if topics[topic].created=0 then topics[topic].created:=date;
      if date<topics[topic].created then topics[topic].created:=date;
     end;
    finally
     cSect.Leave;
    end;
   end;
   LogMsg('Forum data loaded');
   // Индексация
   IndexForumData;
  end;

initialization
 InitCritSect(cSect,'Search');
finalization
 DeleteCritSect(cSect);
end.
