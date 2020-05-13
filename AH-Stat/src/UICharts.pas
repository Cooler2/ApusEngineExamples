// Элементы UI для всевозможных графиков и диаграмм
// Модуль включает как сами классы диаграмм, так и отрисовщик для них
//
// Существуют следующие виды диаграмм:
// 1. Дискретные - показывают числовые значения фиксированного набора параметров (шкалы могут быть нелинейными)
//   1.1 - секторная (Pie)
//   1.2 - горизонтальная (Bar) - набор строк со шкалами и значениями
//   1.3 - вертикальная (Column/Combo) - линейно-столбцовая, может иметь две шкалы
// Наборы данных могут показываться как по отдельности, так и складываясь

// 2. Вещественные - показывают какие-либо параметры в непрерывном двумерном пространстве
//   Позволяют отображать несколько наборов данных различными способами в одном и том же пространстве
//   a) линейный график
//   b) распределение точек (scatter)
//   c) heat map, произвольное изображение

// 3. Временная диаграмма - Time Chart - показывает параметры во времени.
//   Позволяет отображать в едином пространстве параметры 2-х типов:
//   a) моментальные значения некоторой величины (график)
//   b) количество событий за интервал времени (график или столбцы)

unit UICharts;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface
uses MyServis,EngineAPI,UIClasses,AnimatedValues;

const
  UIChartDrawerID:integer=27; // Can be changed to avoid conflicts

  setColors:array[0..3] of cardinal=($FF600000,$FF002070,$FF006020,$FF605000);

  // Глобальные настройки шрифтов и цветов диаграмм и таблиц
  // ---
  // Шрифт для заголовков диаграмм
  chartTitleFont:cardinal=0;
  chartTitleColor:cardinal=$FF000000;
  // Шрифт для подписей
  chartMainFont:cardinal=0;
  chartMainColor:cardinal=$FF000000;
  // Шрифт для мелких подписей
  chartSmallFont:cardinal=0;
  chartSmallColor:cardinal=$FF000000;

  chartBGcolor:cardinal=0;

  // Цвета таблиц
  tableFixedRowColor:cardinal=$FFc5c7cf;
  tableGroupRowColor:cardinal=$FFd4dce1;
  tableRowColor1:cardinal=$FFFFFFFF;
  tableRowColor2:cardinal=$FFf6f2ed;

  tableMainFont:cardinal=0;

type
  // Типы дискретной диаграммы
  TChartType=(ctColumns,  // Столбцы (ключевой параметр расположен на оси X)
              ctRows,     // Горизонтальные строки (ключевой параметр расположен на оси Y)
              ctPie       // секторная диаграмма
  );

  // Способы отображения серии данных (для диаграмм типа ctColumns)
  TChartDataType=(cdtBar,     // прямоугольники
                  cdtLine,    // линейный график
                  cdtScatter  // набор точек
  );

  // Набор данных для диаграммы (серия)
  TChartData=record
   name:WideString; // Название параметра (серии)
   dataType:TChartDataType; // способ отображения параметра
   color:cardinal; // Цвет отрисовки
   usedScale:integer; // 0 - левая шкала, 1 - правая шкала (только для столбцовых диаграмм)
   xValues:FloatArray; // для непрерывных диаграмм - значения X
   values:FloatArray; // значения серии для каждого значения ключевого параметра
   labels:WStringArr; // метки, показываемые при наведении мыши (опционально, если нет - показывается значение)
  end;

  // Базовый класс для элементов, которые а) умеют сами себя рисовать б) содержат критсекцию для доступа к данным
  TUIDataView=class(TUIControl)
   constructor Create(width_,height_:single;parent_:TUIControl;name_:string);
   destructor Destroy; override;
   procedure Lock; virtual; // необходимо вызывать при любом изменении/обращении к данным
   procedure Unlock(modified:boolean=true); virtual;
  private
   tFont,mFont,tFontColor,mFontColor:cardinal;
   cs:TMyCriticalSection;
   changed:boolean; // данные изменились - требуется перерисовка
   procedure Draw; virtual; abstract;
  end;


  // Класс простых значений
  // Представляет собой горизонтальный ряд блоков, где каждый блок имеет заголовок (название параметра) а также список значений под ним
  TUISimpleTable=class(TUIDataView)
   names:WStringArr;
   values:array of WStringArr;
   font1,font2:cardinal;
   constructor Create(width_,height_:single;font1_,font2_:cardinal;pNames:WideString;parent_:TUIControl;name:string);
   procedure ClearData; virtual;
   procedure AddRow(st:WideString); virtual;
  private
   procedure Draw; override;
  end;


  // ЭТО БАЗОВЫЙ КЛАСС ДИАГРАММЫ
  // Рисуется как картинка, обновляемая при изменении данных
  // На уровне отрисовки может реагировать на мышь
  TUIGenericChart=class(TUIDataView)
   title:WideString;
   names:WStringArr; // имена по ключевой оси (для Pie chart - это имена каждой диаграммы)
   data:array of TChartData; // серии данных
   constructor Create(width_,height_:single;title_:WideString;parent_:TUIControl;name_:string);
  protected
   img:TTextureImage; // картинка диаграммы
   procedure Draw; override;
   procedure BuildImage; virtual;
  end;

  // Дискретная диаграмма горизонтального типа: по оси X расположены ключи, по Y - значения (столбиками или линейным графиком)
  TUISimpleChart=class(TUIGenericChart)
   minValue,maxValue:double; // ограничители шкалы
   stacked:boolean; // true - все столбцы рисуются один над другим, false - рисуются рядом
  protected
   procedure Draw; override;
   procedure BuildImage; override;
  end;

  // Вещественный график (
  TUIRealChart=class(TUIGenericChart)
   procedure BuildImage; override;
  end;

  TUITimeChart=class(TUIDataView)

  end;

  // Таблица

  TRowType=(rtNone,      // Строка отсутствует
            rtGroupRow,  // Групповая строка
            rtRow);      // обычная строка

  TTableCellType=(tctString, // просто строка
                  tctNumber, // просто число
                  tctPercent, // число, отображается в виде процентов
                  tctMoney);  // число, форматируется как денежная сумма    

  TTableRow=record
   category:WideString;
   cells:WStringArr;
   rowType:TRowType;
   height:integer;
   subHeight:TAnimatedValue;
   yPos:integer; // internal use
  end;
  TTableRows=array of TTableRow;

  TTableColumn=record
   width:integer;
   caption:widestring;
   align:TTextAlignment;
   dataType:TTableCellType;
  end;
  TTableColumns=array of TTableColumn;

  TUITable=class(TUIDataView)
   constructor Create(width_,height_:single;parent_:TUIControl;name_:string);
   procedure Draw; override;
   procedure onMouseButtons(button:byte;state:boolean); override;

   // Интерфейс данных
   procedure Reset; virtual; // используется для очистки таблицы перед занесением данных
   procedure AddColumn(width:integer;caption:WideString;align:TTextAlignment;cellType:TTableCellType); virtual;
   procedure AddRow(height:integer;category,title:widestring); virtual;
   procedure AddCell(value:widestring); virtual;
   procedure Commit(hasHeader,hasFooter:integer;collapsed:boolean;sortBy:integer=0); virtual;  // Завершает формирование данных таблицы
  protected
   // Промежуточные данные
   sCols:TTableColumns;
   sRows:TTableRows;
   curCell:integer;
   // подготовленные данные для отрисовки
   cols:TTableColumns;
   contentHeight:integer; // суммарная высота нефиксированных строк
   yStart,yEnd:integer; // начальная и конечная координаты области данных (скроллинга)
   rows:TTableRows;
   header,footer:TTableRow; // последняя строка с итогами
   sortedBy:integer; // номер столбца, по которому сортировка (1..N - по убыванию, -1...-N - по возрастанию, 0 - без сортировки)
   procedure UpdateTableData;
   procedure ExpandRow(r:integer);
  end;


 procedure InitUICharts;

 function UISimpleTable(name:string):TUISimpleTable;
 function UIDiscreteChart(name:string):TUIGenericChart;
 function UIRealChart(name:string):TUIRealChart;
 function UISimpleChart(name:string):TUISimpleChart;
 function UITable(name:string):TUITable;


implementation
 uses SysUtils,types,Colors,FastGFX,engineTools,UIRender;

 function UISimpleTable(name:string):TUISimpleTable;
  begin
   result:=FindControl(name) as TUISimpleTable;
   ASSERT(result is TUISimpleTable);
  end;

 function UIDiscreteChart(name:string):TUIGenericChart;
  begin
   result:=FindControl(name) as TUIGenericChart;
   ASSERT(result is TUIGenericChart);
  end;

 function UIRealChart(name:string):TUIRealChart;
  begin
   result:=FindControl(name) as TUIRealChart;
   ASSERT(result is TUIRealChart);
  end;

 function UISimpleChart(name:string):TUISimpleChart;
  begin
   result:=FindControl(name) as TUISimpleChart;
   ASSERT(result is TUISimpleChart);
  end;

 function UITable(name:string):TUITable;
  begin
   result:=FindControl(name) as TUITable;
   ASSERT(result is TUITable);
  end;

 procedure CustomDrawer(control:TUIControl);
  begin
   if control is TUIDataView then TUIDataView(control).Draw;
  end;

 procedure InitUICharts;
  begin
   RegisterUIStyle(UIChartDrawerID,CustomDrawer,'UICharts');
  end;

{ TUIChart }

procedure TUIGenericChart.BuildImage;
begin
 changed:=false;
end;

constructor TUIGenericChart.Create(width_,height_:single;title_:WideString;parent_:TUIControl;name_:string);
begin
 inherited Create(width_,height_,parent_,name_);
 title:=title_;
 changed:=true;
 img:=nil;
end;

procedure TUIGenericChart.Draw;
var
 width,height:integer;
begin
 Lock;
 try
   // Размер изменился?
   width:=round(size.x);
   height:=round(size.y);
   if (img<>nil) and ((img.width<>width) or (img.height<>height)) then texman.FreeImage(img);
   // Данные изменились?
   if changed or (img=nil) then begin
    if img=nil then
     img:=texman.AllocImage(width,height,pfTrueColorAlpha,0,'chart_img') as TTextureImage;
    img.Lock;
    try
     FillRect(img.data,img.pitch,0,0,width-1,height-1,chartBGcolor);
     BuildImage;
    finally
     img.Unlock;
    end;
   end;

   painter.DrawImage(globalRect.Left,globalRect.Top,img);

 finally
  Unlock(false);
 end;

end;

{ TUISimpleTable }

procedure TUISimpleTable.AddRow(st: WideString);
begin
 Lock;
 try
  SetLength(values,length(values)+1);
  values[high(values)]:=splitW('|',st);
 finally
  Unlock;
 end;
end;

procedure TUISimpleTable.ClearData;
begin
 Lock;
 try
  SetLength(values,0);
 finally
  Unlock;
 end;
end;

constructor TUISimpleTable.Create(width_, height_: single;font1_,font2_:cardinal;pNames:WideString;
  parent_: TUIControl;name:string);
begin
 inherited Create(width_,height_,parent_,name);
 Lock;
 try
  font1:=font1_;
  font2:=font2_;
  names:=splitW('|',pNames);
 finally
  Unlock;
 end;
end;

procedure TUISimpleTable.Draw;
 var
  x1,y1,x2,y2:integer;
  x,y,dy,i,n,step:integer;
  c,f:cardinal;
  st:string;
  r:TRect;
begin
 cs.Enter;
 try
  r:=GetPosOnScreen;
  x1:=r.Left; x2:=r.Right;
  y1:=r.Top; y2:=r.Bottom;
  y:=(y1+y2) div 2+5;
  c:=$FF000000;
  f:=font2;
  if length(values)>1 then f:=ScaleFont(f,0.9);
  if length(names)=0 then exit;
  step:=round(17+10/(length(values)+0.5));
  dy:=round(step*(length(values)*0.5+0.25));
  for i:=0 to high(names) do begin
   x:=x1+round((i+0.5)*(x2-x1)/length(names));
   painter.TextOutW(font1,x,y-dy,c,names[i],taCenter);
  end;
  if length(values)=0 then exit;
  inc(y,round(size.y*0.14));
  dec(y,(step div 2)*high(values));
  for n:=0 to high(values) do begin
   c:=setColors[n];
   for i:=0 to high(names) do begin
    x:=x1+round((i+0.5)*(x2-x1)/length(names));
    painter.TextOutW(f,x,y,c,values[n][i],taCenter,toDontTranslate);
   end;
   y:=y+step;
  end;
 finally
  cs.Leave;
 end;
end;

{ TUIDataView }

constructor TUIDataView.Create(width_,height_: single; parent_: TUIControl;
  name_: string);
begin
 inherited Create(width_,height_,parent_,name_);
 style:=UIChartDrawerID;
 InitCritSect(cs,'DV_'+name_);
 tFont:=chartTitleFont;
 tFontCOlor:=chartTitleColor;
 mFont:=chartMainFont;
 mFontColor:=chartMainColor;
end;

destructor TUIDataView.Destroy;
begin
  inherited;
  DeleteCritSect(cs);
end;

procedure TUIDataView.Lock;
begin
 cs.Enter;
end;

procedure TUIDataView.Unlock(modified: boolean);
begin
 if modified then changed:=true;
 cs.Leave;
end;

{ TUISimpleChart }
const
 scaleList:array[1..22] of single=(0.02,0.05,0.1,0.2,0.3,0.5,1,2,3,5,10,20,30,50,100,200,300,500,1000,2000,5000,10000);

procedure TUISimpleChart.BuildImage;
var
 i,j,baseY,x1,x2,y1,stepY,xx,l:integer;
 stepX,scaleY,minY,maxY,maxValue,prvY,curY:double;
begin
 // img уже залочена и очищена
 SetRenderTarget(img.data,img.pitch,img.width,img.height);
 painter.SetTextTarget(img.data,img.pitch);

 maxValue:=0;
 for i:=0 to high(data) do
  for j:=0 to high(data[i].values) do
   maxValue:=Max2d(maxValue,data[i].values[j]);

 baseY:=img.height-25;
 x1:=4; x2:=img.width-15-round(2*ln(100+maxValue));
 y1:=8;
 if title<>'' then inc(y1,12);
 j:=5; // кол-во линий сетки
 while (baseY-y1)/j>25 do inc(j,5);
 stepY:=(baseY-y1) div j; // шаг сетки
 i:=1;
 scaleY:=scaleList[i]; // какое значение приходится на 1 линию
 while scaleY*j<maxValue do begin
  inc(i);
  scaleY:=scaleList[i];
  if i>=high(scaleList) then break;
 end;
 scaleY:=scaleY/stepY; // на пиксель

 for i:=1 to j do
  FillRect(x1,baseY-i*stepY,x2,baseY-i*stepY,$20404040+$30000000*(byte(i mod 5=0)));
 xx:=(x2+round(size.x)) div 2;
 for i:=0 to j do begin
  if (stepY<20) and (i mod 2=1) then continue;
  painter.TextOutW(chartSmallFont,x2+3,baseY-i*stepY+4,chartSmallColor,FloatToStrF(scaleY*i*stepY,ffGeneral,5,0),
   taLeft,toDrawToBitmap+toDontTranslate);
 end;

 FillRect(x1,baseY,x2,baseY,$FF000000);
 FillRect(x1,y1,x1,baseY,$FF000000);
 FillRect(x2,y1,x2,baseY,$FF000000);

 // Data
 stepX:=(x2-x1)/length(names);
 l:=0;
 for i:=0 to high(names) do
  inc(l,painter.TextWidthW(chartSmallFont,names[i]));
 l:=1+l div (length(names)+1); 
 for i:=0 to high(names) do begin
  if (stepX<l+2) and (i mod 2=0) then continue; // подписи через раз, если не влазят
  xx:=x1+round(stepX*(i+0.5));
  painter.TextOutW(chartSmallFont,xx,baseY+12,chartSmallColor,names[i],taCenter,toDrawToBitmap+toDontTranslate);
 end;

 if length(data)>0 then begin
  l:=round(0.8*stepX/length(data));
  for i:=0 to high(data) do // серия
   with data[i] do begin
    if data[i].dataType=cdtLine then begin
     for j:=0 to high(values) do begin
      xx:=x1+round(stepX*(j+0.5));
      curY:=values[j]/scaleY;
      if j>0 then SmoothLine(xx-stepX,baseY-prvY,xx,baseY-curY,color,0.7);
      prvY:=curY;
      FillCircle(xx,baseY-curY,1.5,color);
     end;
    end;
    if data[i].dataType=cdtBar then begin
     for j:=0 to high(values) do begin
      xx:=x1+round(stepX*(j+0.1))+1+i*l;
      curY:=round(values[j]/scaleY);
      FillRect(xx,baseY-round(curY),xx+l-1,baseY,$80000000+color and $FFFFFF);
     end;
    end;
   end;
 end;

 if title<>'' then painter.TextOutW(chartTitleFont,x1+5,y1-2,chartTitleColor,title,taLeft,toDrawToBitmap);
 changed:=false;
end;

procedure TUISimpleChart.Draw;
begin
 inherited;
end;

{ TUITable }

procedure TUITable.Reset;
begin
 SetLength(sCols,0);
 SetLength(sRows,0);
end;

procedure TUITable.AddColumn(width: integer; caption: WideString;
  align: TTextAlignment; cellType: TTableCellType);
var
 n:integer;
begin
 n:=length(sCols);
 SetLength(sCols,n+1);
 sCols[n].width:=width;
 sCols[n].caption:=caption;
 sCols[n].align:=align;
 sCols[n].dataType:=cellType;
end;

procedure TUITable.AddRow(height: integer; category, title: widestring);
var
 n:integer;
begin
 n:=length(sRows);
 SetLength(sRows,n+1);
 SetLength(sRows[n].cells,length(sCols));
 sRows[n].rowType:=rtRow;
 sRows[n].height:=height;
 sRows[n].subHeight.Init(0);
 sRows[n].cells[0]:=title;
 sRows[n].category:=category;
 curCell:=1;
end;

procedure TUITable.AddCell(value: widestring);
begin
 if curCell>high(sCols) then exit;
 sRows[high(sRows)].cells[curCell]:=value;
 inc(curCell);
end;

procedure TUITable.Commit(hasHeader, hasFooter: integer; collapsed: boolean; sortBy:integer=0);
var
 i,j,k,l,h:integer;
 grouped:boolean;
 values:array of double;

function GetCellValue(row,col:integer):double;
 var
  st:string;
 begin
  result:=0;
  if cols[k].dataType=tctString then exit;
  result:=ParseFloat(rows[i].cells[k]);
  if cols[k].dataType=tctPercent then result:=result/100;
 end;

function FormatCellValue(col:integer;value:double):string;
 begin
  case cols[k].dataType of
   tctString,tctNumber:result:=FloatToStrF(value,ffGeneral,8,0);
   tctPercent:result:=FloatToStrF(value*100,ffGeneral,4,1)+' %';
   tctMoney:result:=FormatMoney(value,0);
  end;
 end;

procedure InsertRow(r:integer);
 var
  i:integer;
 begin
  SetLength(rows,length(rows)+1);
  for i:=high(rows) downto r+1 do
   rows[i]:=rows[i-1];
 end;

begin
 Lock;
 try
  cols:=Copy(sCols);
  header.height:=hasHeader;
  if hasHeader>0 then begin
   header.rowType:=rtRow;
   SetLength(header.cells,length(cols));
   for k:=0 to high(cols) do
    header.cells[k]:=cols[k].caption;
  end;
  SetLength(values,length(cols));

  rows:=Copy(sRows);
  // Группировка (при необходимости)
  grouped:=false;
  for i:=1 to high(rows) do
   if rows[i].category<>rows[i-1].category then begin
    grouped:=true; break;
   end;
  // Группировка по категориям
  if grouped then begin
   // Сортировка по категориям
   for i:=0 to high(rows)-1 do
    for j:=i+1 to high(rows) do
     if rows[j].category<rows[i].category then Swap(rows[j],rows[i],sizeof(rows[i]));
   // Вставка групповых строк
   i:=0;
   repeat
    j:=i;
    while (j<=high(rows)) and (rows[j].category=rows[i].category) do inc(j);
    l:=i;
    // сейчас i..(j-1) - строки для группировки
    for k:=1 to high(cols) do values[k]:=0;
    while i<j do begin
     for k:=1 to high(cols) do values[k]:=values[k]+GetCellValue(i,k);
     inc(i);
    end;
    // Заполнение строки
    InsertRow(l);
    SetLength(rows[l].cells,length(cols));
    rows[l].rowType:=rtGroupRow;
    rows[l].subHeight.Init(0);
    rows[l].cells[0]:=rows[l].category;
    for k:=1 to high(cols) do
     rows[l].cells[k]:=FormatCellValue(k,values[k]);
    h:=0;
    for k:=l+1 to j do inc(h,rows[k].height);
    rows[l].subHeight.Init(h);
    inc(i); 
   until i>high(rows);
  end;

  // Заполнение итогов (если есть)
  if hasfooter>0 then begin
   SetLength(footer.cells,length(cols));
   footer.rowType:=rtRow;
   footer.cells[0]:='';
   for k:=1 to high(cols) do values[k]:=0;
   for i:=0 to high(rows) do
    if rows[i].rowType=rtRow then
     for k:=1 to high(cols) do values[k]:=values[k]+GetCellValue(i,k);

   for k:=1 to high(cols) do
    footer.cells[k]:=FormatCellValue(k,values[k]);
  end else
   footer.rowType:=rtNone;
  footer.height:=hasFooter;

  sortedBy:=sortBy;
 finally
  Unlock;
 end;
end;

constructor TUITable.Create(width_, height_: single; parent_: TUIControl;
  name_: string);
begin
 inherited;
 transpMode:=tmOpaque;
 Reset;
end;

procedure TUITable.Draw;
 var
  x1,y1,x2,y2,y,yy,nextY:integer;
  i,colCount,rowCount:integer;
  xPos:array[0..20] of integer;
  inner:integer;
  color:cardinal;
 procedure DrawRow(y:integer;var r:TTableRow;color:cardinal;special:integer=0);
  var
   j,yy:integer;
   align:TTextAlignment;
  begin
   yy:=y+r.height-1;
   painter.FillRect(x1,y,x2,yy,color);
   if r.rowType=rtGroupRow then begin
    painter.DrawLine(x1,y,x2,y,ColorAdd(color,$0A0A0A));
    painter.DrawLine(x1,yy,x2,yy,ColorSub(color,$0A0A0A));
    yy:=1+(y+yy)div 2;
    if r.subHeight.FinalValue=0 then
     painter.FillTriangle(x1+4,yy-5,x1+9,yy,x1+4,yy+5,$C0202020,$C0202020,$C0202020)
    else
     painter.FillTriangle(x1+6-4,yy-2,x1+6+4,yy-2,x1+6,yy+3,$C0202020,$C0202020,$C0202020);
   end;
   for j:=0 to high(r.cells) do begin
    painter.SetClipping(Rect(xPos[j],y,xPos[j+1]-1,y+r.height));
    align:=cols[j].align;
    if special=1 then align:=taLeft;

    painter.TextOutW(tableMainFont,xPos[j]+2,y+round(r.height*0.7),$FF000000,r.cells[j],align,
      toDontTranslate,xPos[j+1]-xPos[j]-4);
    painter.ResetClipping;
    if j=colCount then break;
   end;
  end;
begin
 cs.Enter;
 try
  UpdateTableData;
  rowCount:=length(rows);
  if rowCount=0 then exit;
  x1:=globalRect.Left;
  y1:=globalRect.Top;
  x2:=globalrect.Right;
  y2:=globalrect.Bottom;
//  if scrollerV.visible then dec(x2,scrollerV.width);
  // Колонки
  colCount:=length(cols);
  xPos[0]:=x1+10;
  for i:=1 to colCount do
   xPos[i]:=xPos[i-1]+cols[i-1].width;
  // фиксированные строки

  if footer.rowType<>rtNone then begin
   DrawRow(yEnd,footer,tableFixedRowColor,2);
   painter.FillGradrect(x1,(yEnd+y2) div 2,x2,y2,$FFFFFF,$50FFFFFF,true);
   painter.DrawLine(x1,yEnd,x2,yEnd,$40FFFFFF);
  end;

  if header.rowType<>rtNone then begin
   DrawRow(y1,header,tableFixedRowColor,1);
   for i:=1 to colCount do begin
    painter.DrawLine(xPos[i]-1,y1,xPos[i]-1,yStart,ColorSub(tableFixedRowColor,$101010));
    painter.DrawLine(xPos[i],y1,xPos[i],yStart,ColorAdd(tableFixedRowColor,$101010));
   end;
   painter.FillGradrect(x1,(y1+yStart) div 2,x2,yStart-1,$FFFFFF,$50FFFFFF,true);
   painter.DrawLine(x1,yStart-1,x2,yStart-1,$20606060);
  end;

  y:=yStart-round(scrollerV.value);
  inner:=0;
  painter.SetClipping(Rect(x1,yStart,x2,yEnd));
  try
   for i:=0 to high(rows) do begin
    if (inner=0) and (rows[i].rowType=rtRow) then inner:=1;
    if (inner>0) and (rows[i].rowType=rtGroupRow) then begin
     inner:=0;
     y:=nextY;
     painter.ResetClipping;
    end;
    // Строка вообще видна?
    yy:=y+rows[i].height;
    if inner=0 then
     color:=tableGroupRowColor
    else
     if inner and 1=0 then color:=tableRowColor1
      else color:=tableRowColor2;
    rows[i].yPos:=y;
    if (y<painter.GetClipping.Bottom) and (yy>=painter.GetClipping.Top) then DrawRow(y,rows[i],color);
    y:=yy;
    if rows[i].rowType=rtGroupRow then begin
     nextY:=y+rows[i].subHeight.IntValue;
     painter.SetClipping(Rect(x1,y,x2,nextY));
     inner:=1;
    end else
     inc(inner);
   end;
   if inner>0 then painter.ResetClipping;
  finally
   painter.ResetClipping;
  end;

 finally
  cs.Leave;
 end;
end;

procedure TUITable.ExpandRow(r:integer);
var
 j,h:integer;
begin
  j:=r+1; h:=0;
  while (j<=high(rows)) do begin
   if rows[j].rowType<>rtRow then break;
   inc(h,rows[j].height);
   inc(j);
   end;
   rows[r].subHeight.Animate(h,200,spline1);
end;

procedure TUITable.onMouseButtons(button: byte; state: boolean);
var
 i,j,h:integer;
begin
 inherited;
 Lock;
 try
 if state and (button=1) and (game.mouseY>=yStart) and (game.mouseY<yEnd) then
  for i:=0 to high(rows) do
   if (rows[i].rowType=rtGroupRow) and
      (game.mouseY>=rows[i].yPos) and (game.mouseY<rows[i].yPos+rows[i].height) then begin
    if rows[i].subHeight.FinalValue=0 then
     ExpandRow(i)
    else
     rows[i].subHeight.Animate(0,200,spline1);
   end;
 finally
  Unlock(false);
 end;
end;

procedure TUITable.UpdateTableData;
var
 i:integer;
 inner:boolean;
begin
 if scrollerV=nil then
  scrollerV:=TUIScrollBar.Create(10,yEnd-yStart+1,'TableScrollV',self);
 scrollerV.SetPos(0,yStart,pivotTopLeft);
 scrollerV.visible:=false;

 contentHeight:=0; inner:=false;
 for i:=0 to high(rows) do begin
  if rows[i].rowType=rtGroupRow then inner:=false;
  if inner then continue;
  inc(contentHeight,rows[i].height);
  if rows[i].rowType=rtGroupRow then begin
   inc(contentHeight,rows[i].subHeight.IntValue);
   inner:=true;
  end;
 end;
 yStart:=globalRect.Top; yEnd:=globalRect.Bottom;
 if length(rows)=0 then exit;
 if header.rowType<>rtNone then inc(yStart,header.height);
 if footer.rowType<>rtNone then dec(yEnd,footer.height);
 if yEnd<=yStart then exit;
 if contentHeight>(yEnd-yStart+1) then begin
  scrollerV.visible:=true;
  scrollerV.horizontal:=false;
  scrollerV.position.x:=size.x-10;
  scrollerV.position.y:=yStart-globalRect.Top;
  scrollerV.size.y:=yEnd-yStart;
  scrollerV.max:=contentHeight;
  scrollerV.pagesize:=(yEnd-yStart)+1;
  scrollerV.step:=60;
 end else begin
  scrollerV.visible:=false;
  scrollerV.value:=0;
 end;

end;

{ TUIRealChart }

procedure TUIRealChart.BuildImage;
var
 i,j,baseY,x1,x2,y1,stepY,stepX,l:integer;
 scaleY,minY,maxY,maxValue,prvY,curY:double;
 scaleX,minX,maxX,prvX,curX:double;
begin
 // img уже залочена и очищена
 SetRenderTarget(img.data,img.pitch,img.width,img.height);
 painter.SetTextTarget(img.data,img.pitch);

 // Сетка по оси Y
 maxValue:=0;
 for i:=0 to high(data) do
  for j:=0 to high(data[i].values) do
   maxValue:=Max2d(maxValue,data[i].values[j]);

 baseY:=img.height-25;
 x1:=4; x2:=img.width-15-round(2*ln(100+maxValue));
 y1:=8;
 if title<>'' then inc(y1,12);
 j:=5; // кол-во линий сетки по вертикали
 while (baseY-y1)/j>25 do inc(j,5);
 stepY:=(baseY-y1) div j; // шаг сетки
 i:=1;
 scaleY:=scaleList[i]; // какое значение приходится на 1 линию
 while scaleY*j<maxValue do begin
  inc(i);
  scaleY:=scaleList[i];
  if i>=high(scaleList) then break;
 end;
 scaleY:=scaleY/stepY; // на пиксель

 // Отрисовка сетки
 for i:=1 to j do
  FillRect(x1,baseY-i*stepY,x2,baseY-i*stepY,$20404040+$30000000*(byte(i mod 5=0)));
 for i:=1 to j do begin
  if (stepY<20) and (i mod 2=1) then continue;
  painter.TextOutW(chartSmallFont,x2+3,baseY-i*stepY+4,chartSmallColor,FloatToStrF(scaleY*i*stepY,ffGeneral,5,0),
   taLeft,toDrawToBitmap+toDontTranslate);
 end;

 // Сетка по оси X
 maxValue:=0;
 for i:=0 to high(data) do
  for j:=0 to high(data[i].xValues) do
   maxValue:=Max2d(maxValue,data[i].xValues[j]);

 j:=5; // кол-во линий сетки по оси X
 while (x2-x1)/j>25 do inc(j,5);
 stepX:=(x2-x1) div j; // шаг сетки
 i:=1;
 scaleX:=scaleList[i]; // какое значение приходится на 1 линию
 while scaleX*j<maxValue do begin
  inc(i);
  scaleX:=scaleList[i];
  if i>=high(scaleList) then break;
 end;
 scaleX:=scaleX/stepX; // на пиксель

 // Отрисовка сетки
 for i:=1 to j do
  FillRect(x1+i*stepX,y1,x1+i*stepX,baseY,$20404040+$30000000*(byte(i mod 5=0)));
 for i:=0 to j do begin
  if (stepX<20) and (i mod 2=1) then continue;
  painter.TextOutW(chartSmallFont,x1+i*stepX,baseY+13,chartSmallColor,FloatToStrF(scaleX*i*stepX,ffGeneral,5,0),
   taCenter,toDrawToBitmap+toDontTranslate);
 end;

 // Границы
 FillRect(x1,baseY,x2,baseY,$FF000000);
 FillRect(x1,y1,x1,baseY,$FF000000);
 FillRect(x2,y1,x2,baseY,$FF000000);

 // Data
 if length(data)>0 then begin
  l:=round(0.8*stepX/length(data));
  for i:=0 to high(data) do // серия
   with data[i] do begin
   
    if data[i].dataType=cdtLine then begin
     for j:=0 to high(values) do begin
      curX:=xValues[j]/scaleX;
      curY:=values[j]/scaleY;
      if j>0 then SmoothLine(x1+prvX,baseY-prvY,x1+curX,baseY-curY,color,1);
      prvY:=curY; prvX:=curX;
     end;
    end;

    if data[i].dataType=cdtScatter then begin
     for j:=0 to high(values) do begin
      curX:=x1+xValues[j]/scaleX;
      curY:=baseY-values[j]/scaleY;
      FillCircle(curX,curY,2.4,color);
      FillCircle(curX,curY,1.5,color);
      DrawPixelAA(curX,curY,color);
     end;
    end;
   end;
 end;

 if title<>'' then painter.TextOutW(chartTitleFont,x1+5,y1-2,chartTitleColor,title,taLeft,toDrawToBitmap);
 changed:=false;

end;

end.
