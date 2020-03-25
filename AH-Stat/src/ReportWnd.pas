// Функциональность окна отчётов
unit ReportWnd;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface
 uses UIScene;
 var
  fontMain,fontSmall,fontLarge,fontBold,fontSerif,fontAwesome:cardinal;

  mainScene:TUIScene;

 procedure ShowReportsWnd;
 procedure CloseReportsWnd;

implementation
 uses
{$IFnDEF FPC}
  windows,
{$ELSE}
  LCLIntf, LCLType, LMessages,
{$ENDIF}
  MyServis,SysUtils,classes,mainWnd,
   conScene,eventman,GLgame,EngineAPI,engineTools,UIClasses,customUI,UICharts,Reports,Data;
 const
  reportsList=
   '02|Показатели игроков;'+
   '11|Новые регистрации;'+
   // Отчёты на базе таблицы payments
   '20|Финансовые показатели;'+ // Информация о платежах (выручке): по месяцам/неделям, по покупкам, по странам, по источникам и т.д.
   '21|Платёжная активность';  // Выручка относительно создания аккаунта

 type
  TMainScene=class(TUIScene)
   procedure Render; override;
  end;


  // Панель с отчётом (включая все элементы управления: выбор типа отчёта -> параметры отчета -> сам отчёт
  TUIReport=class(TUIControl)
   rType:integer;
   constructor Create;

   // сохранение всех настроек
   function SaveSettings:TReportSettings;
   // загрузка всех настроек отчёта
   procedure LoadSettings(s:TReportSettings);

   procedure CopyParam(group,idx:integer);

  protected
   container:TUIContainer; // левая панель с настройками
   view:TUIContainer; // правая часть с содержимым
   procedure SelectReportType(rt:integer);
   procedure InitRetentionReport;
   procedure InitFinanceReport; 
   procedure InitPaymentsReport;
   procedure InitPlayersOverviewReport;
   procedure InitActivityReport;
   procedure InitDueltypesReport;
   procedure InitPlayerBaseReport;      
  end;

  // Поток, который занимается обновлением данных отчёта
  TDataThread=class(TThread)
   procedure Execute; override;
  end; 

 var
  curReport:TUIReport;
  thread:TDataThread;
//  changed:boolean;

{ TUIReport }

procedure TUIReport.CopyParam(group, idx: integer);
 var
  s1,s2:AnsiString;
 begin
  if group<2 then exit;
  if group>high(container.children) then exit;
  if not (container.children[group] is TUIPanel) then exit;
  s1:=inttostr(group-1)+inttostr(idx);
  s2:=inttostr(group)+inttostr(idx);
  UIComboBox('ParamName'+s2).curItem:=UIComboBox('ParamName'+s1).curItem;
  UIComboBox('Operation'+s2).curItem:=UIComboBox('Operation'+s1).curItem;
  UIEditBox('Value'+s2).realtext:=UIEditBox('Value'+s1).realText;
 end;

constructor TUIReport.Create;
  var
   par:TUIControl;
   panel:TUIPanel;
   combo:TUIComboBox;
   repTypes:WStringArr;
   sa:WStringArr;
   i:integer;
  begin
   par:=mainScene.UI;
   inherited Create(par.size.x,par.size.y,par,'Report');
   rType:=-1;
   curReport:=self;
   style:=0;
   styleinfo:='FFC0C8D0';
   container:=TUIContainer.Create(380,0,orVertical,smLeft,self);
   container.name:='Settings';
   view:=TUIContainer.Create(size.x-380,0,orVertical,smRight,self);
   view.name:='ReportData';
   view.position.x:=380;
   // Панель типа отчёта
   panel:=TUIPanel.Create(380,75,5,'Тип отчёта',container,'ReportType');
   // Выбор типа
   sa:=splitW(';',reportsList);
   for i:=0 to high(sa) do
    AddString(repTypes,sa[i]);
   combo:=TUIComboBox.Create(360-20*2,24,fontMain,repTypes,panel,'SelectReportType');
   combo.defaultText:='Выберите тип отчёта';
   Link('UI\COMBOBOX\OnSelect\SelectReportType','Report\SelectType');
  end;

// -------------------------------------------------------------------------------------------
// 02 - основные показатели группы игроков: Retention, ARPU, ARPPU и т.д.
// -------------------------------------------------------------------------------------------
procedure TUIReport.InitPlayersOverviewReport;
 var
  panel:TUIPanel;
  cont:TUIContainer;
  table:TUITable;
  rTable:TUIRealChart;
  i,c:integer;
 begin
  panel:=TUIPanel.Create(view.clientWidth-20,80,5,'Основные показатели игроков',view,'PlayersOverview');
  TUISimpleTable.Create(600,85,fontSmall,fontLarge,'Всего игроков|Платящих|Конверсия|Выручка|ARPPU|ARPU',panel,'Table02_1');

  panel:=TUIPanel.Create(view.clientWidth-20,80,5,'Удержание игроков',view,'PlayersRetention');
  TUISimpleTable.Create(600,85,fontSmall,fontLarge,'Прошли кампанию|Остались 1дн|Остались 3дн|Остались 10дн|Остались 30дн',panel,'Table02_2');

  cont:=TUIContainer.Create(view.clientWidth,200,orHorizontal,smNone,view);
  cont.name:='PlayerInfoGroup';

  panel:=TUIPanel.Create(round(cont.clientWidth*0.25),80,0,'Тэги',cont,'PlayersTags');
  table:=TUITable.Create(100,100,panel,'PlayersTagsTable');
  table.Snap(smParent);

  panel:=TUIPanel.Create(round(cont.clientWidth*0.25),80,0,'OS',cont,'PlayersOS');
  table:=TUITable.Create(100,100,panel,'PlayersOSTable');
  table.Snap(smParent);

  panel:=TUIPanel.Create(round(cont.clientWidth*0.3),80,0,'Videocards',cont,'PlayersVideo');
  table:=TUITable.Create(100,100,panel,'PlayersVideoTable');
  table.Snap(smParent);

  panel:=TUIPanel.Create(round(cont.clientWidth*0.2),80,0,'OpenGL',cont,'PlayersOpenGL');
  table:=TUITable.Create(100,100,panel,'PlayersOpenGLTable');
  table.Snap(smParent);


  panel:=TUIPanel.Create(view.clientWidth-20,200,8,'Слава и опыт',view,'FameScatter');
  cont:=TUIContainer.Create(100,200,orHorizontal,smNone,panel);
  cont.name:='FameScatterGroup';
  cont.spacing:=16;
  cont.resizeToContent:=true;
  for i:=0 to 3 do begin
   rTable:=TUIRealChart.Create(panel.clientWidth/4-32,200,'Режим '+inttostr(i),cont,'FameScatter'+inttostr(i));
  end;

 end;

// -------------------------------------------------------------------------------------------
// 03 - Игровая активность игроков (players+eventlog - игровые сессии и т.д.)
// -------------------------------------------------------------------------------------------
procedure TUIReport.InitActivityReport;
 var
  panel:TUIPanel;
  cont:TUIContainer;
  table:TUITable;
  i,c:integer;
 begin
  panel:=TUIPanel.Create(view.clientWidth-20,80,5,'Основные показатели игроков',view,'PlayersOverview');
  TUISimpleTable.Create(600,85,fontSmall,fontLarge,'Всего игроков|Платящих|Конверсия|Выручка|ARPPU|ARPU',panel,'Table02_1');

  panel:=TUIPanel.Create(view.clientWidth-20,80,5,'Удержание игроков',view,'PlayersRetention');
  TUISimpleTable.Create(600,85,fontSmall,fontLarge,'Прошли кампанию|Остались 1дн|Остались 3дн|Остались 10дн|Остались 30дн',panel,'Table02_2');

  cont:=TUIContainer.Create(view.clientwidth-20,200,orHorizontal,smNone,view);
  panel:=TUIPanel.Create(cont.clientwidth/3,80,0,'Тэги',cont,'PlayersTags');
  table:=TUITable.Create(100,100,panel,'PlayersTagsTable');
  table.Snap(smParent);
 end;

// -------------------------------------------------------------------------------------------
// 10 - Подробный отчёт по Retention
// -------------------------------------------------------------------------------------------
procedure TUIReport.InitRetentionReport;
 var
  panel:TUIPanel;
  chart:TUIGenericChart;
  sa:WStringArr;
 begin
  panel:=TUIPanel.Create(view.clientwidth-16,280,5,'User Retention',view,'Retention');

  sa:=SplitW(';','1d;3d;7d;14d;28d');
  // 1. Простой Retention
  chart:=TUISimpleChart.Create(250,200,'Simple Retention',panel,'SimpleRetention');
  // 2. Rolling retention
  chart:=TUISimpleChart.Create(250,200,'Rolling Retention',panel,'RollingRetention');
  chart.position.x:=chart.position.x+300;
 end;

// -------------------------------------------------------------------------------------------
// 11 - Приток, отток, размер активной аудитории
// -------------------------------------------------------------------------------------------
procedure TUIReport.InitPlayerBaseReport;
 var
  panel:TUIPanel;
  chart:TUIGenericChart;
  i,j:integer;
  con:TUIContainer;
begin
  panel:=TUIPanel.Create(view.clientwidth-16,280,5,'Новые регистрации игроков',view,'NewPlayers');
  con:=TUIContainer.Create(panel.clientwidth-64,0,orVertical,smNone,panel);

  // 1. Регистрации по неделям
  chart:=TUISimpleChart.Create(panel.clientwidth-20,200,'По неделям',panel,'WeeklyReg');

  // 2. Регистрации по месяцам
  chart:=TUISimpleChart.Create(panel.clientwidth-20,200,'По месяцам',panel,'MonthlyReg');
  chart.MoveBy(0,220);
end;

// -------------------------------------------------------------------------------------------
// 20 - Финансовые показатели
// -------------------------------------------------------------------------------------------
procedure TUIReport.InitFinanceReport;
 var
  panel:TUIPanel;
  chart:TUIGenericChart;
  i,j:integer;
  con:TUIContainer;
 begin
  panel:=TUIPanel.Create(view.clientwidth-16,280,5,'Выручка игры',view,'Revenue');
  con:=TUIContainer.Create(panel.clientwidth-64,0,orVertical,smNone,panel);

  // 1. Выручка по неделям
  chart:=TUISimpleChart.Create(panel.clientwidth-20,200,'Выручка по неделям',panel,'WeeklyRevenue');

  // 2. Выручка по месяцам
  chart:=TUISimpleChart.Create(panel.clientwidth-20,200,'Выручка по месяцам',panel,'MonthlyRevenue');
  chart.MoveBy(0,220);
 end;

// -------------------------------------------------------------------------------------------
// 21 - Платёжная активность игроков
// -------------------------------------------------------------------------------------------
procedure TUIReport.InitPaymentsReport;
 var
  panel:TUIPanel;
  chart:TUIGenericChart;
  i,j:integer;
  con:TUIContainer;
 begin
  panel:=TUIPanel.Create(view.clientwidth-16,280,5,'Средняя выручка по аккаунтам',view,'Payments');
//  con:=TUIContainer.Create(0,0,orVertical,smParent,panel);
  // 1. График распределения платежей относительно даты создания аккаунта
  // Линейный график: по x - дни с момента регистрации аккаунта,
  //  по Y - суммарное кол-во доната на игрока, совершённое за указанный период
  chart:=TUISimpleChart.Create((view.clientwidth-32)/2,200,'Выручка по возрасту аккаунта ($,сут)',panel,'PaymentsPerAge1');
  for i:=1 to 14 do AddString(chart.names,IntToStr(i));

  chart:=TUISimpleChart.Create((view.clientwidth-32)/2,200,'Выручка по возрасту аккаунта ($,сут)',panel,'PaymentsPerAge2');
  chart.MoveBy(round(view.clientwidth-16) div 2,0);
  for i:=1 to 14 do AddString(chart.names,IntToStr(i*7));
 end;

// -------------------------------------------------------------------------------------------
// 31 - Типы боёв
// -------------------------------------------------------------------------------------------
procedure TUIReport.InitDueltypesReport;
 var
  panel:TUIPanel;
  chart:TUIGenericChart;
  i,j:integer;
  con:TUIContainer;
 begin
  panel:=TUIPanel.Create(view.clientwidth-16,280,5,'Средняя выручка по аккаунтам',view,'Payments');
//  con:=TUIContainer.Create(0,0,orVertical,smParent,panel);
  // 1. График распределения платежей относительно даты создания аккаунта
  // Линейный график: по x - дни с момента регистрации аккаунта,
  //  по Y - суммарное кол-во доната на игрока, совершённое за указанный период
  chart:=TUISimpleChart.Create((view.clientwidth-32)/2,200,'Выручка по возрасту аккаунта ($,сут)',panel,'PaymentsPerAge1');
  for i:=1 to 14 do AddString(chart.names,IntToStr(i));

  chart:=TUISimpleChart.Create((view.clientwidth-32)/2,200,'Выручка по возрасту аккаунта ($,сут)',panel,'PaymentsPerAge2');
  chart.MoveBy((view.clientwidth-16)/2,0);
  for i:=1 to 14 do AddString(chart.names,IntToStr(i*7));
 end;


procedure TUIReport.LoadSettings(s: TReportSettings);
 var
  i,j,idx:integer;
  cb:TUIComboBox;
  eb:TUIEditBox;
  st:AnsiString;
  param,oper:integer;
  value:AnsiString;
 begin
  UICritSect.Enter;
  try
   if rType<>s.rType then SelectReportType(s.rType);
   for i:=1 to 4 do
    for j:=1 to 6 do begin
     param:=-1; oper:=-1; value:='';
     if i-1<=high(s.groups) then
      with s.groups[i-1] do
       if j-1<=high(conditions) then begin
        param:=conditions[j-1].parameter;
        oper:=conditions[j-1].oper;
        value:=conditions[j-1].value;
       end;

     st:='ParamName'+inttostr(i)+inttostr(j);
     if FindControl(st,false)<>nil then
      UIComboBox(st).SetCurItemByTag(param);

     st:='Operation'+inttostr(i)+inttostr(j);
     if FindControl(st,false)<>nil then
      UIComboBox(st).SetCurItemByTag(oper);

     st:='Value'+inttostr(i)+inttostr(j);
     if FindControl(st,false)<>nil then
      UIEditBox(st).realText:=DecodeUTF8(value);
    end;

  finally
   UICritSect.Leave;
  end;
 end;

function TUIReport.SaveSettings: TReportSettings;
 var
  i,n,j:integer;
  fl:boolean;
 procedure SaveFilter(panel:TUIPanel;var group:TGroup);
  var
   i,n:integer;
   con:TUIControl;
   combo,combo2:TUIComboBox;
   edit:TUIEditBox;
  begin
   n:=0;
   SetLength(group.conditions,n);
   for i:=0 to high(panel.children) do begin
    con:=panel.children[i];
    if not (con.ClassType=TUIControl) then exit;
    combo:=con.children[0] as TUIComboBox;
    if combo.curItem>0 then begin
     combo2:=con.children[1] as TUIComboBox;
     edit:=con.children[2] as TUIEditBox;
     inc(n);
     SetLength(group.conditions,n);
     with group.conditions[n-1] do begin
      parameter:=combo.curTag;
      oper:=combo2.curTag;
      value:=edit.text; // wide -> utf8 ?
     end;
    end;
   end;
  end;
 begin
  UICritSect.Enter;
  try
   result.rType:=rType;
   n:=0;
   SetLength(result.groups,0);
   for i:=1 to high(container.children) do
    if container.children[i].name='Filter' then begin
     inc(n);
     SetLength(result.groups,n);
     SaveFilter(container.children[i] as TUIPanel,result.groups[n-1]);
    end;
   // убрать пустые группы в конце
   for i:=high(result.groups) downto 1 do begin
    fl:=true;
    for j:=0 to high(result.groups[i].conditions) do
     if result.groups[i].conditions[j].value<>'' then fl:=false;
    if fl then SetLength(result.groups,i);
   end;
  finally
   UICritSect.Leave;
  end;
 end;

// При выборе типа отчёта - создание UI для него
procedure TUIReport.SelectReportType(rt: integer);
 var
  group:integer;
 procedure AddGroupFilters(n:integer=1);
  var
   group:TUIControl;
   panel:TUIPanel;
   combo:TUIComboBox;
   edit:TUIEditBox;
   btn:TUIButton;
   sa,sb:WStringArr;
   i,j:integer;
   st,digits:AnsiString;
  begin
   panel:=TUIPanel.Create(360,155,2,'Фильтр сегмента '+inttostr(n),container,'Filter');
   case n of
    1:panel.styleinfo:='FFA06060';
    2:panel.styleinfo:='FF2040A0';
    3:panel.styleinfo:='FF209040';
   end;
   // Какой показывать набор параметров
   digits:='01234';
   if rt in [20,21] then digits:=digits+'5';
   sa:=SplitW(';',paramList);
   // Уберём ненужные для данного типа отчёта параметры
   j:=0;
   while j<=high(sa) do
    if pos(copy(sa[j],1,1),digits)=0 then RemoveString(sa,j)
     else inc(j);

   sb:=SplitW(';',operationList);

   for i:=1 to 4 do begin
    st:=inttostr(n)+inttostr(i);
    group:=TUIControl.Create(362,25,panel,'FilterCondition'+st);
    group.SetPos(2,4+(i-1)*28);
    group.paddingTop:=2;

    // параметр
    combo:=TUIComboBox.Create(120,22,fontMain,sa,group,'ParamName'+st);
    combo.SetPos(1,0);
    combo.defaultText:='параметр';
    combo.curItem:=0;
    combo.popup.scrollerV.Resize(8,-1);
    combo.maxlines:=20;
    // оператор
    combo:=TUIComboBox.Create(90,22,fontMain,sb,group,'Operation'+st);
    combo.SetPos(128,0);
    combo.curItem:=0;
    // Значение
    edit:=TUIEditBox.Create(110+25*byte(n=1),20,'Value'+st,fontMain,$FF000000,group);
    edit.SetPos(223,1);
    edit.backgnd:=$FFFFFFFF;
    // Кнопка копирования
    if n>1 then begin
     btn:=TUIButton.Create(22,22,'CopyParam'+inttostr(n)+inttostr(i),UStr(WideChar($F0C5)),fontAwesome,group);
     btn.SetPos(338,0);
     btn.enabled:=n>1;
     btn.hint:=UStr('Скопировать фильтр из предыдущей группы');
     btn.styleinfo:='FFE0E0D9 FF303030 40909090 A0FFFFFF A0FFFFFF 70A0A0A0';
     Link('UI\OnButtonClick\'+btn.name,'Report\'+btn.name);
    end;
   end;

   // Кнопка экспорта группы игроков
   btn:=TUIButton.Create(48,17,'Export\'+inttostr(n),'Export',fontMain,panel);
   btn.SetPos(310,-21);
   btn.parentClip:=false;
   btn.order:=-1;
   btn.hint:=UStr('Экспорт данных, соответствующих этому фильтру, в файл');
   Link('UI\OnButtonClick\'+btn.name,'Report\ExportData',n);
  end;

 begin
  if rType=rt then exit;
  rType:=rt;
  UICritSect.Enter;
  try
  // Настройка UI для выбора параметров отчёта
  // 1. Удалить все элементы
  while length(container.children)>1 do
   container.children[1].Free;
  // 2. Создать необходимые элементы
  for group:=1 to 3 do
   AddGroupFilters(group);
  // Удалить содержимое предыдущих отчётов
  view.Clear;

  LogMessage('Selected report: %d',[rType]);
  // Настройка (создание) UI для нового отчёта
  case rType of
   02:InitPlayersOverviewReport;
   03:InitActivityReport;
//   10:InitRetentionReport;
   11:InitPlayerBaseReport;
   20:InitFinanceReport;
   21:InitPaymentsReport;
  end;
//  changed:=true;
  finally
   UICritSect.Leave;
  end;
 end;

{ TMainScene }

procedure TMainScene.Render;
begin
  inherited;
  if isBusy>0 then DrawSpinner(game.renderWidth div 2,game.renderHeight div 2,40,$80202020);
end;

{ TDataThread }

procedure BuildReport(rs:TReportSettings);
begin
 LogMessage('BuildReport %d',[rs.rType]);
 case rs.rType of
  02:begin
       if playersOverview=nil then
         playersOverview:=TPlayersOverview.Create;
       curReportData:=playersOverview;
     end;
  11:begin
       if newPlayersData=nil then
         newPlayersData:=TNewPlayersData.Create;
       curReportData:=newPlayersData;
  end;
  20:begin
       if paymentsOverview=nil then
         paymentsOverview:=TPaymentsOverview.Create;
       curReportData:=paymentsOverview;
     end;
  21:begin
       if paymentsReportData=nil then
         paymentsReportData:=TPaymentsReportData.Create;
       curReportData:=paymentsReportData;
     end;
 end;
 inc(isBusy);
 if curReportData<>nil then curReportData.Build(rs);
 dec(isBusy);
 LogMessage('Report %d done',[rs.rType]);
end;

procedure TDataThread.Execute;
var
 rs:TReportSettings;
 st,old:AnsiString;
 prevType:integer;
begin
 RegisterThread('DataThread');
 BuildDerivedData; 
 old:=''; prevType:=-1;
 repeat
  sleep(300);
  UICritSect.Enter;
  try
   // Скопировать инфу о том, что именно надо делать
   rs:=curReport.SaveSettings;
  finally
   UICritSect.Leave;
  end;
  // Settings changed?
  try
   st:=rs.ExportToString;
   if st<>old then begin
    old:=st;
    BuildReport(rs);
    if (rs.rType>0) and (rs.rType=prevType) then begin
     ctl.SetStr('ReportSettings\Report'+inttostr(rs.rType),st);
     ctl.Save;
    end else
     prevType:=rs.rType;
   end;
  except
   on e:Exception do ErrorMessage(ExceptionMsg(e));
  end;
 until terminated;
 LogMessage('DataThread terminated');
 UnregisterThread;
end;

 // event='Report\xxx'
 function EventHandler(event:EventStr;tag:TTag):boolean;
  var
   r:TUIReport;
   p:pointer;
   c:TUIComboBox;
   idx:integer;
   sa:AStringArr;
   img:TUIImage;
   re:TRect;
   st:AnsiString;
   rs:TReportSettings;
  begin
   delete(event,1,7);
   event:=UpperCase(event);
   if copy(event,1,9)='COPYPARAM' then begin
    idx:=StrToIntDef(copy(event,10,2),0);
    curreport.CopyParam(idx div 10,idx mod 10);
   end;
   if copy(event,1,3)='IMG' then begin
    idx:=StrToInt(copy(event,4,2));
    img:=TUIImage(pointer(tag));
    re:=img.GetPosOnScreen;
{    case idx of
     02:DrawImage02(re.Left,re.Top,re.Right,re.Bottom,img);
    end;}
   end;
   if (event='SELECTTYPE') and (tag<>0) then begin
    c:=TUIComboBox(pointer(tag));
    if c.curItem<0 then exit;
    idx:=c.tags[c.curItem];
    sa:=splitA(';',reportsList);
    r:=TUIReport(c.parent.parent.parent);
    r.SelectReportType(idx);
    // Последние использованные настройки отчёта
    st:=ctl.GetStr('ReportSettings\Report'+inttostr(idx),'');
    if st<>'' then begin
     rs.ImportFromString(st);
     r.LoadSettings(rs);
    end;
   end;

   if (event='EXPORTDATA') and (curReportData<>nil) then curReportData.ExportData(tag);
  end;

 procedure CloseReportsWnd;
  begin
   if game<>nil then begin
    ForceLogMessage('Closing report WND');
    if thread<>nil then begin
     thread.Terminate;
     thread.WaitFor;
    end;
    game.Stop;
    repeat sleep(1) until game.terminated;
    FreeAndNil(game);
   end;
   RemoveEventHandler(EventHandler,'Report');
  end;

 procedure ShowReportsWnd;
  var
   settings:TGameSettings;
  begin
   // Создание и конфигурация объекта игры
   game:=TGLGame.Create;
   with settings do begin
    title:='Аналитика Astral Heroes';
    width:=min2(1400,game.screenWidth-40);
    height:=game.screenHeight-100;
    colorDepth:=32;
    refresh:=0;
    VSync:=1;
    mode.displayMode:=dmFixedWindow;
    mode.displayFitMode:=dfmStretch;
    mode.displayScaleMode:=dsmDontScale;
    showSystemCursor:=true;
    zbuffer:=0;
    stencil:=false;
    multisampling:=0;
    slowmotion:=true;
   end;
   game.Settings:=settings;
   // Запуск игры
   game.Run;
   // Загрузка и инициализация всего необходимого
   Link('Engine\Cmd\Exit','AHStat\CloseWnd');
   game.ToggleCursor(crDefault);
   // Шрифты
   painter.LoadFont('droidSans.ttf','DroidSans');
   painter.LoadFont('Roboto-Condensed.ttf','Roboto');
   painter.LoadFont('droidSans-bold.ttf','DroidSansBold');
   painter.LoadFont('droidSerif-Regular.ttf','DroidSerif');
   painter.LoadFont('fontawesome-webfont.ttf','Awesome');
   fontMain:=painter.GetFont('DroidSans',10);
   fontSmall:=painter.GetFont('DroidSans',8.5);
   fontLarge:=painter.GetFont('DroidSans',14);
   fontBold:=painter.GetFont('DroidSansBold',11.5);
   fontAwesome:=painter.GetFont('Awesome',11);

   chartTitleFont:=painter.GetFont('DroidSans',12);
   chartMainFont:=painter.GetFont('DroidSans',9);
   chartSmallFont:=painter.GetFont('DroidSans',8);
   tableMainFont:=painter.GetFont('DroidSans',9);
//   tableFixedRowColor:=$FFC0C4C8;
//   tableGroupRowColor:=$FFD0D8DA;
//   tableRowColor1:=$FFFFFFFF;
//   tableRowColor2:=$FFE0FFFF;

   InitUI;
   InitCustomUI;
   InitUICharts;

   mainScene:=TMainScene.Create;
   TUIReport.Create;
   SetEventHandler('Report',EventHandler,emInstant);

   mainScene.SetStatus(ssActive);
   AddConsoleScene;
   thread:=TDataThread.Create(false);
//   changed:=true;

   // Разрешаем отрисовку
   game.active:=true;
  end;
  

end.
