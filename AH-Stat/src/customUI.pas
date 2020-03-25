// Здесь реализация дополнительных (не входящих в движок) классов UI общего назначения
// (т.е. таких, которые могут быть применены и в других проектах)
unit customUI;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface
 uses MyServis,EngineAPI,UIClasses;

 const
  statStyle = 2; // стиль для отрисовки элементов UI данного модуля

 type
  TOrientation=(orVertical,   // вложенные элементы располагаются один за другим по вертикали
                orHorizontal  // вложенные элементы располагаются по горизонтали
                );

  // Панель с рамкой и заголовком. Подстраивает свой размер под высоту содержимого, центрирует по горизонтали
  TUIPanel=class(TUIControl)
   caption:WideString;
   constructor Create(width_, height_,padding_: single; caption_: WideString; parent_: TUIControl;name_:string);
   procedure onTimer; override;
  private
   fPadding:single;
   procedure SetPadding(p:single);
  public
   property padding:single read fPadding write SetPadding;
  end;

  // Элемент предназначен для позиционирования вложенных элементов
  TUIContainer=class(TUIControl)
   arrange:TOrientation;
   resizeToContent:boolean; // Ширина(высота) будет равна сумме элементов
   resizeChildren:boolean; // Ширина(высота) элементов устанавливается так, чтобы они занимали всю ширину контейнера
   alignChildren:boolean; // Высота(ширина) элементов выставляется равной высоте контейнера
   spacing:integer;
   constructor Create(width_,height_:single;orient:TOrientation;snap:TSnapMode;parent_:TUIControl);
   procedure onTimer; override;
  end;

 procedure InitCustomUI;

implementation
 uses CrossPlatform,SysUtils,eventman,engineTools,ReportWnd,UIRender,types,Geom2d;

 function EventHandler(event:EventStr;tag:TTag):boolean;
  var
   c:TUIControl;
  begin
   result:=true;
   event:=UpperCase(event);

{   // Вызов списка вариантов
   if (event='UI\COMBOBOX\DROPDOWN') and (tag<>0) then begin
    c:=pointer(tag);
    if (c is TUIComboBox) then TUIComboBox(c).onDropDown;
    if (c.parent<>nil) and (c.parent is TUIComboBox) then TUIComboBox(c.parent).onDropDown;
   end;

   if event='UI\LISTBOX\ONSELECT\COMBOBOXPOPUP' then begin
    c:=pointer(tag);
    TUIComboBox(c.customPtr).onDropDown;
   end;}

  end;

 procedure DrawPanel(x1,y1,x2,y2:integer;panel:TUIPanel);
  const
    margin=6;
    blue=$FF8080A0;
  var
   y0:integer;
   c:cardinal;
  begin
   inc(x1,margin); inc(y1,margin);
   dec(x2,margin); dec(y2,margin);
   if (x1>x2) or (y1>y2) then exit;
   y0:=min2(y1+23,y2); // начиная отсюда идёт белый цвет
   c:=HexToInt(panel.styleinfo);
   if c=0 then c:=blue;
   painter.FillRect(x1+1,y1+1,x2-1,y0-1,c);
   if y2>y0 then painter.FillRect(x1+1,y0,x2-1,y2-1,$FFF3F2F0);
   painter.Rect(x1,y1,x2,y2,blue);
   painter.DrawLine(x1+1,y2+1,x2+1,y2+1,$30202020);
   painter.DrawLine(x2+1,y1+1,x2+1,y2+1,$30202020);
   painter.DrawLine(x1+2,y2+2,x2+2,y2+2,$10202020);
   painter.DrawLine(x2+2,y1+2,x2+2,y2+2,$10202020);
   painter.TextOutW(fontBold,(x1+x2) div 2,y1+17,$FFF0F0F0,panel.caption,taCenter);
  end;

 procedure DrawButton(x1,y1,x2,y2:integer;button:TUIButton);
  var
   x,y:integer;
   c:cardinal;
  begin
  end;

 procedure CustomDrawer(control:TUIControl);
  var
   x1,y1,x2,y2,h:integer;
  begin
   with control do begin
    x1:=globalrect.Left;
    y1:=globalrect.Top;
    x2:=globalrect.Right-1;
    y2:=globalrect.Bottom-1;
   end;
   if (control is TUIButton) then DrawButton(x1,y1,x2,y2,control as TUIButton);
   if control is TUIPanel then DrawPanel(x1,y1,x2,y2,control as TUIPanel);
//   if control is TUIComboBox then DrawComboBox(x1,y1,x2,y2,control as TUIComboBox);
  end;

 procedure InitCustomUI;
  begin
   RegisterUIStyle(statStyle,CustomDrawer);
   SetEventHandler('UI\ComboBox',EventHandler);
   SetEventHandler('UI\ListBox',EventHandler);
  end;

{ TUIContainer }

constructor TUIContainer.Create(width_, height_: single; orient: TOrientation;
  snap: TSnapMode; parent_: TUIControl);
var
 x0,y0:single;
begin
 x0:=0; y0:=0;
 spacing:=0;
 arrange:=orient;
 resizeChildren:=false;
 alignChildren:=true;
 resizeToContent:=false;
 if snap in [smLeft,smRight,smParent] then height_:=parent_.size.y;
 if snap in [smTop,smBottom,smParent] then width_:=parent_.size.x;
 case snap of
  smRight:x0:=parent_.size.x-width_;
  smBottom:y0:=parent_.size.y-height_;
 end;
 inherited Create(width_,height_,parent_,'Container');
 SetPos(x0,y0,pivotTopLeft);
 timer:=1;
end;

procedure TUIContainer.onTimer;
var
 i:integer;
 p:single;
begin
 timer:=1;
 // Выравнивание дочерних элементов
 p:=0;
 for i:=0 to high(children) do begin
  if children[i].order<0 then continue;
  if arrange=orVertical then begin
   if alignChildren and (children[i].size.x<>size.x) then
     children[i].Resize(size.x,-1);
   children[i].position.x:=0;
   children[i].position.y:=p;
   p:=p+children[i].size.y+spacing;
  end else begin
   if alignChildren and (children[i].size.y<>size.y) then
     children[i].Resize(-1,size.y);
   children[i].position.y:=0;
   children[i].position.x:=p;
   p:=p+children[i].size.x+spacing;
  end;
 end;
 if resizeToContent then
  if arrange=orVertical then size.y:=p
   else size.x:=p;
end;

{ TUIPanel }

constructor TUIPanel.Create(width_, height_,padding_: single; caption_: WideString;
  parent_: TUIControl;name_:string);
begin
 inherited Create(width_,height_,parent_,name_);
 caption:=caption_;
 style:=statStyle;
 timer:=1;
 padding:=padding_;
 transpmode:=tmOpaque;
end;

procedure TUIPanel.onTimer;
var
 i:integer;
 bbox:TRect2s;
 dx,dy:single;
begin
 inherited;
 timer:=1;
 SetPadding(padding);

 if length(children)=0 then exit;
 bbox.Init;
 for i:=0 to high(children) do begin
  if children[i].order<0 then continue;  // out of order elements
  bbox.Include(children[i].GetRectInParentSpace);
 end;
 if bbox.IsEmpty then exit;

 dy:=-bbox.y1;
 size.y:=paddingTop+paddingBottom+Max2d(5,bbox.Height);
 dx:=(size.x-bbox.width)/2-bbox.x1-paddingLeft;
 if (dx<>0) or (dy<>0) then begin
  for i:=0 to high(children) do begin
   if children[i].order<0 then continue;
   VectAdd(children[i].position,Point2s(dx,dy));
  end;
 end;
end;

procedure TUIPanel.SetPadding(p: single);
begin
 fPadding:=p;
 paddingLeft:=7+p; paddingRight:=7+p;
 paddingTop:=7+22+p; paddingBottom:=7+p;
end;

end.
