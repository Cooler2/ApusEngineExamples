// Вспомогательный модуль: реализует рабочие потоки, выполняющие "длинные" запросы,
// путём вызова ф-ций из других модулей
{$R+}
unit workers;
interface
 threadvar workerID:integer; // 1..N

 var
  maxQueueSize:integer;
  workersTimestamp:TDateTime;

 procedure InitWorkers;
 procedure DoneWorkers;

 // Добавляет запрос внутрисерверного текстового протокола
 // (т.е. создает таск для асинхронного исполнения в рабочем потоке)
 // userID - от кого запрос (только авторизованный!)
 //          (0 - нет юзера)
 // CRID - индекс запроса/соединения, ожидающего результата данного запроса
 //      (0 - если запрос вспомогательный и ответ в конкретное соединение не нужен)
 //       формат 00yyxxxx, где yy - requestRnd, xxxx - индекс
 // если request начинается с # - это запрос к ServerLogic
 procedure AddTask(userID,CRID:integer;data:array of const);
 function TaskQueueSize:integer;

 function GetCurrentTasks:string;

implementation
 uses windows,MyServis,SysUtils,Logging,globals,classes,
  ServerLogic,CustomLogic,net;

 type
  TWorker=class(TThread)
   id:integer;
   curTask:string;
   taskExecuting:boolean;
   tasksExecuted:integer;
   procedure Execute; override;
  end;

 var
  qSignal:THANDLE;
  wList:array[1..MAX_WORKERS] of TWorker;
  wCount,wRunning:integer;

  // список запросов для асинхронной обработки
  tasks:array[0..1023] of string;
  rUser,rCon:array[0..1023] of integer;
  rFirst,rLast:byte; // индекс первого занятого таска и индекс первого свободного таска

 const
  mask = $FF;

 function GetCurrentTasks:string;
  var
   i:integer;
   st:string;
  begin
   result:='';
   try
   for i:=1 to wCount do
    if wList[i]<>nil then begin
     st:='';
     if wList[i].taskExecuting then st:=wList[i].curTask;
     result:=result+Format('WT=%d: %d [%s] ',[i,wList[i].tasksExecuted,st]);
    end;
   except
   end;
  end;

 procedure AddTask(userID,CRID:integer;data:array of const);
  var
   task:string;
   qSize:integer;
  begin
   task:=FormatMessage(data);
   EnterCriticalSection(gSect);
   try
    inc(serverStat.tasks);
    tasks[rLast]:=task;
    rUser[rLast]:=userID;
    rCon[rLast]:=CRID;
    if LOG_TASKS and (minLogMemLevel=0) then
      LogMsg(' AddTask #'+inttostr(rLast)+': '+task,logDebug,9);
    rLast:=(rLast+1) and mask;
    if rLast=rFirst then begin
     LogMsg('ERROR! Task queue overflow!',logError,9);
     rLast:=(rLast-1) and mask;
     raise EError.Create('Task queue overflow!');
    end;
    qSize:=TaskQueueSize;
    if qSize>maxQueueSize then maxQueueSize:=qSize;
   finally
    LeaveCriticalSection(gSect);
   end;
   SetEvent(qSignal);
  end;

 function TaskQueueSize:integer;
  begin
   result:=rLast-rFirst;
   if result<0 then result:=result+mask+1;
  end;  

 procedure InitWorkers;
  var
   i:integer;
  begin
   qSignal:=CreateEvent(nil,false,false,'');
   wCount:=NUM_WORKERS;
   wRunning:=0;
   ForceLogMessage('Initializing '+inttostr(wCount)+' worker threads...');
   for i:=1 to wCount do begin
    wList[i]:=TWorker.Create(true);
    wList[i].id:=i;
    wList[i].Resume;
    sleep(100);
   end;
  end;

 procedure DoneWorkers;
  var
   i:integer;
  begin
   AddTask(0,0,['SERVERSHUTDOWN']);
   Sleep(50);
   ForceLogMessage('Terminating worker threads...');
   for i:=1 to wCount do begin
    wList[i].Terminate;
    SetEvent(qSignal); // разбудить спящие потоки, чтобы они быстрее завершились
   end;
   i:=0;
   while (wRunning>0) and (i<12) do begin
    inc(i);
    sleep(i*10);
   end;
   if i=12 then
    ForceLogMessage('Some workers stalls!');
   ForceLogMessage('Terminated');
   CloseHandle(qSignal);
  end;

{ TWorker }
 procedure TWorker.Execute;
  var
   task,response:string;
   userID,CRID,tid:integer;
   time:int64;
  begin
   InterlockedIncrement(wRunning);
   try
   RegisterThread('Worker'+inttostr(id));
   tasksExecuted:=0;
   workerID:=ID;
   InitThreadDatabase(ID);
   repeat
    sleep(1+(workerID-1)*10);
//    WaitForSingleObject(qSignal,20);
    // Get next task
    EnterCriticalSection(gSect);
    try
     workersTimestamp:=Now;
     if rFirst<>rLast then begin
      tid:=rFirst;
      task:=tasks[rFirst];
      tasks[rFirst]:='';
      userID:=rUser[rFirst];
      CRID:=rCon[rFirst];
      rFirst:=(rFirst+1) and mask;
     end else
      continue;
    finally
     LeaveCriticalSection(gSect);
    end;
    // No task -> wait again
    if task='' then continue;
    // Handle task
    try
     time:=MyTickCount;
     if LOG_TASKS and (minLogMemLevel=0) then
       LogMsg(inttostr(id)+' Task #'+inttostr(tid)+': '+task,logDebug,9);
     // Обработка запроса
     if task[1]='#' then
      response:=''
     else begin
      curTask:=task;
      taskExecuting:=true;
      response:=ExecAsyncTask(CRID,userID,task);
      taskExecuting:=false;
      inc(tasksExecuted);
      time:=MyTickCount-time;
      if LOG_TASKS and (minLogMemLevel=0) then
        LogMsg(inttostr(id)+' Task #'+inttostr(tid)+' done in '+IntToStr(time),logDebug+byte(time>100),9);
     end;
     // Отправка результата
     if (response<>'') and (CRID>0) then SendMsg(CRID,response);
    except
     on e:exception do LogMsg('Worker error: '+ExceptionMsg(e)+' request: '+task,logError,1);
    end;
   until terminated;
   DoneThreadDatabase(ID);
   InterlockedDecrement(wRunning);
   except
    on e:Exception do LogMsg('Fatal worker error: '+ExceptionMsg(e),logCritical,9);
   end;
   ForceLogMessage('Worker '+inttostr(id)+' finished');
  end;

initialization
 rFirst:=0; rLast:=0;  
end.
