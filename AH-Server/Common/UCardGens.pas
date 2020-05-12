unit UCardGens;

interface
const maxcardgen=256;
      maxpairgen=180;
      mincgvalue=-24;
      maxcgvalue=24;
      cgshift=6;
      minpgvalue=-150;
      maxpgvalue=150;
      pairchangevalue=6;
type

tCardGens=array[1..maxcardgen] of integer;
tGenData=array[1..maxcardgen,mincgvalue..maxcgvalue] of integer;
pCardGens=^tcardgens;

tPairGens=array[1..maxpairgen,1..maxpairgen] of smallint;
tPairData=array[1..maxpairgen,1..maxpairgen,minpgvalue..maxpgvalue] of integer;

tGenVault=object
 HandGensData:tGenData;
 CreatureGensData:tGenData;
 EnemyCreatureGensData:tGendata;
 DraftGensData:tGenData;
end;

tnumbers=array of integer;

var GenVault:tGenVault;
    PairData,ExternalPairData,TempPairData:tPairData;

procedure GenerateRandomCardGens(var cg:tcardgens;var basiscardgens:tcardgens);
procedure ClearGens(var cg:tcardgens);
procedure LoadCardGensFromFile(var cg:tcardgens;filename:string);
procedure SaveOptimalGens(var gd:tgendata;var basiscardgens:tcardgens;filename:string);
procedure PrepareGenReport(var gd:tgendata;var basiscardgens:tcardgens;filename:string);
function GetDistValue(maxdist,dist:integer):integer;
procedure SaveGenVault;
procedure LoadGenVault;
function findmax(n:tnumbers):integer;

procedure GenerateRandomPairGens(var pg:tpairgens);
procedure ClearPairGens(var pg:tpairgens);
procedure ExportPairData(name:string='Inf\pairpowerdr.inf');
procedure SavePairData;
procedure LoadPairData(name:string='Inf\pairpowerdr.inf');

implementation
uses sysutils,cnsts,udict,myservis,ucompai;

function findmax(n:tnumbers):integer;
var d:array[-1000..2000] of double;
    q,w,e,r,t:integer;
    d0,d1,d2:double;
begin
 t:=length(n);
// setlength(d,t);
 for q:=0 to t-1 do
  d[q]:=n[q];
 for q:=2-t to -1 do
  d[q]:=d[-q];
 for q:=t to t*2-2 do
  d[q]:=d[2*t-q-2];
 for q:=1 to t+10{*4 div 3} do
 for w:=3-t to t*2-3 do
 begin
  d0:=d[w-1];
  d1:=d[w];
  d2:=d[w+1];
  d[w-1]:=d0*19/20+d1*1/20;
  d[w]:=d1*18/20+(d0+d2)*1/20;
  d[w+1]:=d1*1/20+d2*19/20;
 end;
 d1:=-999999999;
 result:=-1;
 for q:=t div 10 to t-1-(t div 10) do
 begin
  if d[q]>d1 then
  begin
   result:=q;
   d1:=d[q];
  end;
 end;
end;

function GetDistValue(maxdist,dist:integer):integer;
begin
 if maxdist=0 then
  result:=1
 else
  result:=50+(maxdist-dist)*50 div maxdist;
end;

function mincardgenvalue(card:integer;var basiscardgens:tcardgens):integer;
begin
 result:=basiscardgens[card]-cgshift;
 if result<mincgvalue then
  result:=mincgvalue;;
end;

function maxcardgenvalue(card:integer;var basiscardgens:tcardgens):integer;
begin
 result:=basiscardgens[card]+cgshift;
 if result>maxcgvalue then
  result:=maxcgvalue;;
end;

procedure GenerateRandomCardGens(var cg:tcardgens;var basiscardgens:tcardgens);
var q,w:integer;
begin
 for q:=1 to maxcardgen do
 begin
  w:=mincardgenvalue(q,basiscardgens);
  cg[q]:=random(1+maxcardgenvalue(q,basiscardgens)-w)+w;
 end;
end;

procedure ClearGens(var cg:tcardgens);
begin
 fillchar(cg,sizeof(cg),0);
end;

procedure LoadCardGensFromFile(var cg:tcardgens;filename:string);
var f:file of tCardGens;
begin
 if fileexists(filename)=false then
  forcelogmessage('File '+filename+' NOT FOUND');

 assign(f,filename);
 reset(f);
 read(f,cg);
 close(f);
end;

function GetBlurredValue(var gd:tgendata;var basiscardgens:tcardgens;cardnum,gen,blur:integer):integer;
var q,w,e,r:integer;
begin
 r:=0;
 e:=0;
 for q:=gen-blur to gen+blur do
 if (q>=mincardgenvalue(cardnum,basiscardgens)) and (q<=maxcardgenvalue(cardnum,basiscardgens)) then
 begin
  w:=getdistvalue(blur,abs(q-gen));
  inc(r,gd[cardnum,q]*w);
  inc(e,w);
 end;
 result:=r*1000 div e;
end;

procedure SaveOptimalGens(var gd:tgendata;var basiscardgens:tcardgens;filename:string);
var cg:tcardgens;
    c,q,w,e,r:integer;
    f:file of tCardGens;
    n:tnumbers;
begin
 ClearGens(cg);
 for c:=1 to numcards do
 begin
{  e:=-20;
  r:=-999999999;
  for q:=mincgvalue+3 to maxcgvalue-3 do
  begin
   w:=GetBlurredvalue(gd,c,q,3);
   if w>r then
   begin
    e:=q;
    r:=w;
   end;
  end;
  cg[c]:=e;}
  e:=mincardgenvalue(c,basiscardgens);
  r:=0;
  w:=maxcardgenvalue(c,basiscardgens)-e+1;
  setlength(n,w);
  for q:=0 to w-1 do
  begin
   n[q]:=gd[c,q+e];
   inc(r,abs(n[q]));
  end;
  if r>0 then
   cg[c]:=findmax(n)+e
  else
   cg[c]:=0; 
 end;

 assign(f,filename);
 rewrite(f);
 write(f,cg);
 close(f);
end;

procedure PrepareGenReport(var gd:tgendata;var basiscardgens:tcardgens;filename:string);
var q,w,e,b:integer;
    s:string;
    f:text;

procedure ShowBestGen(c,blur:integer);
var q,w,e,r:integer;
begin
 e:=-20;
 r:=-999999999;
 for q:=mincardgenvalue(c,basiscardgens)+blur to maxcardgenvalue(c,basiscardgens)-blur do
 begin
  w:=GetBlurredvalue(gd,basiscardgens,c,q,blur);
  if w>r then
  begin
   e:=q;
   r:=w;
  end;
 end;
 writeln(f,'  Best gen '+inttostr(e)+' (blur '+inttostr(blur)+'), value='+inttostr(r));
end;

begin
 assign(f,filename);
 rewrite(f);

 for q:=1 to numcards do
 begin
  writeln(f,Simply(cardinfo[q].name));
  ShowBestgen(q,6);
  ShowBestgen(q,3);
  ShowBestgen(q,1);
  ShowBestgen(q,0);
  writeln(f,'');
 end;

 close(f);
end;

procedure SaveGenVault;
var f:file of tGenVault;
begin
 assign(f,'Saves\GenVault.sav');
 rewrite(f);
 write(f,genvault);
 close(f);
end;

procedure LoadGenVault;
var f:file of tGenVault;
begin
 if fileexists('Saves\GenVault.sav') then
 begin
  assign(f,'Saves\GenVault.sav');
  reset(f);
  read(f,genvault);
  close(f);
 end else
  fillchar(genvault,sizeof(genvault),0);
end;

procedure  AddGenVault(fn:string);
var f:file of tGenVault;
    tgn:tGenVault;
    q,w:integer;
begin
 if fileexists(fn) then
 begin
  assign(f,fn);
  reset(f);
  read(f,tgn);
  close(f);
  for q:=1 to maxcardgen do
  for w:=mincgvalue to maxcgvalue do
  begin
   inc(genvault.DraftGensData[q,w],tgn.DraftGensData[q,w]);
   inc(genvault.HandGensData[q,w],tgn.HandGensData[q,w]);
   inc(genvault.CreaturegensData[q,w],tgn.CreaturegensData[q,w]);
   inc(genvault.EnemyCreaturegensData[q,w],tgn.EnemyCreaturegensData[q,w]);
  end;
  DeleteFile(fn);
  SaveGenVault;
 end;
end;

function CardisNew(c:integer):boolean;
begin
 result:=false{(c=16)or(c>154)};
end;


function getmingen(q,w:integer):integer;
begin
 if cardisnew(q) or cardisnew(w) then
  result:=pairpower[q,w]{basispair[q,w]}-pairchangevalue*3
 else
  result:=basispair[q,w]-pairchangevalue;
 if result<minpgvalue then
  result:=minpgvalue;
end;

function getmaxgen(q,w:integer):integer;
begin
 if cardisnew(q) or cardisnew(w) then
  result:=pairpower[q,w]{basispair[q,w]}+pairchangevalue*3
 else
  result:=basispair[q,w]+pairchangevalue;
 if result>maxpgvalue then
  result:=maxpgvalue;
end;

procedure GenerateRandomPairGens(var pg:tpairgens);
var q,w,m1,m2:integer;
begin
 for q:=1 to maxpairgen do
 for w:=q to maxpairgen do
 begin
  m1:=getmingen(q,w);
  m2:=getmaxgen(q,w);
  pg[q,w]:=random(1+m2-m1)+m1;
 end;
 for q:=1 to maxpairgen do
 for w:=1 to q-1 do
 begin
  pg[q,w]:=pg[w,q];
 end;
end;

procedure ClearPairGens(var pg:tpairgens);
begin
 fillchar(pg,sizeof(pg),0);
end;

procedure SavePairData;
var f:file of tPairData;
begin
 assign(f,'Saves\GenPairData.sav');
 rewrite(f);
 write(f,PairData);
 close(f);
end;

procedure LoadPairData(name:string='Inf\pairpowerdr.inf');
var f:file of tPairData;
    needexport:boolean;
    q:integer;
    n1,n2,n3:integer;
begin
 if fileexists('Saves\GenPairData.sav') then
 begin
  assign(f,'Saves\GenPairData.sav');
  reset(f);
  read(f,PairData);
  close(f);
 end else
  fillchar(PairData,sizeof(PairData),0);
 fillchar(ExternalPairData,sizeof(PairData),0);
 needexport:=false;
 for q:=1 to 9 do
 if fileexists('Saves\ExternalPairData'+inttostr(q)+'.sav') then
 begin
  assign(f,'Saves\ExternalPairData'+inttostr(q)+'.sav');
  reset(f);
  read(f,TempPairData);
  close(f);
  for n1:=1 to maxpairgen do
  for n2:=1 to maxpairgen do
  for n3:=minpgvalue to maxpgvalue do
   inc(ExternalPairdata[n1,n2,n3],TempPairData[n1,n2,n3]);
  needexport:=true;
 end;
 if needexport then
  ExportPairData(name);
end;

procedure ExportPairData(name:string='Inf\pairpowerdr.inf');
var q,w,e,r,t,m1,m2,sm:integer;
    n:tnumbers;
    s:string;
begin
 fillchar(pairpowerpl,sizeof(pairpowerpl),0);
 for q:=1 to numcards do
 begin
  for w:=q to numcards do
  begin
   m1:=getmingen(q,w);
   m2:=getmaxgen(q,w);
   e:=m2-m1+1;
   setlength(n,e);
   sm:=0;
   for r:=0 to e-1 do
   begin
    n[r]:=pairdata[q,w,r+m1]+externalpairdata[q,w,r+m1];
    inc(sm,abs(n[r]));
   end;
   if sm>0 then
    t:=findmax(n)+m1
   else
    t:=basispair[q,w];
   if t<-125 then
    t:=125;
   if t>125 then
    t:=125;
   pairpowerpl[q,w]:=t;
   pairpowerpl[w,q]:=t;
  end;
  s:=cardinfo[q].name;
   s:=s+', '+inttostr(pairpowerpl[q,150]);
  logmessage(s);
 end;
{ logmessage('');
 logmessage('[1,151] (costs2) = '+inttostr(pairpowerpl[1,151]));
 logmessage('[1,152] (costs345) = '+inttostr(pairpowerpl[1,152]));
 logmessage('[2,151] (km) = '+inttostr(pairpowerpl[2,151]));
 logmessage('[2,152] (dm) = '+inttostr(pairpowerpl[2,152]));
 logmessage('[3,151] (future) = '+inttostr(pairpowerpl[3,151]));
 logmessage('[3,152] (zerocurve) = '+inttostr(pairpowerpl[3,152]));}
 PairPowerPlSave(name);
end;



end.

