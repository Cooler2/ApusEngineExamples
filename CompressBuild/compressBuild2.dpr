{$APPTYPE CONSOLE}
program compressBuild2;

uses MyServis,SysUtils,zlibEx,DCPMD5a;

{$R+}
var
 f:Text;
 rootDir:string;
 dsr:TSearchRec;
 r:integer;
 dir,prevName:string;
 excludeList:StringArr;
 fileList:string;

 function NeedExclude(st:string):boolean;
  var
   i:integer;
   ex,root:string;
  begin
   result:=false;
   st:=UpperCase(st);
   root:=UpperCase(rootDir);
   for i:=0 to high(excludeList) do begin
    if (copy(excludeList[i],1,2)<>'.\') and (pos(excludeList[i],st)>0) then begin
      result:=true;
    end;
    if (copy(excludeList[i],1,2)='.\') then begin
      ex:=root+copy(excludeList[i],2,200);
      if pos(ex,st)>0 then begin
       result:=true;
      end;
    end;
   end;
   // Включить те файлы, где содержится +XXX
   for i:=0 to high(excludeList) do
    if copy(excludeList[i],1,1)='+' then begin
     ex:=copy(excludeList[i],2,200);
     if pos(ex,st)>0 then
      result:=false;
    end;
  end;

 procedure ProcessFile(fname:string);
  var
   checksum:int64;
   data:file;
   buf,dest:pointer;
   size,size2,fsize,n:integer;
   st:string;
  begin
   if NeedExclude(fname) then exit;
   try
   // Файл еще не сжат?
   write('  ',fname);
   if (fname[length(fname)]<>'_') then begin
    assign(data,fname);
    reset(data,1);
    size:=filesize(data);
    getmem(buf,size);
    blockread(data,buf^,size);
    close(data);
    checksum:=HexToInt(copy(MD5(buf^,size),1,12));

    ZCompress(buf,size,dest,size2,zcMax);

    rewrite(data,1);
    blockwrite(data,size,4);
    blockwrite(data,checksum,8);
    blockwrite(data,dest^,size2);
    close(data);
    fsize:=size2+12;
    fname:=fname+'_';
    if fileExists(fname) then
     DeleteFile(fname);
    rename(data,fname);
    freemem(dest);
    freemem(buf);
    write(' packed ');
   end else begin
    st:=fname;
    setLength(st,length(st)-1);
    // проверка на наличие несжатого (исходного) файла
    // если есть - удалить сжатый
    if FileExists(st) then begin
     delete(fname,1,length(rootDir)+1);
     exit;
    end;
    assign(data,fname);
    reset(data,1);
    fsize:=filesize(data);
    blockread(data,size,4);
    blockread(data,checksum,8);
    close(data);
    write(' handled ');
   end;
   delete(fname,1,length(rootDir)+1);
   if fname[length(fname)]='_' then setLength(fname,length(fname)-1);
   if pos(fname+';',fileList)>0 then begin
    writeln('Duplicated file: ',fname,' - skipped!');
    exit;
   end;
   n:=1;
   while (n<length(fName)) and (n<length(prevName)) do
    if fName[n]=prevName[n] then inc(n)
     else break;
   dec(n);
   if n<5 then n:=0;
   if n>0 then st:=IntToStr(n)+'*'+copy(fName,n+1,length(fName))
    else st:=fName;
   writeln(f,st,';',IntToHex(checksum,12),';',fsize,';',size);
   prevName:=fName;
   fileList:=fileList+prevName+';';
   writeln;
   except
    on e:exception do Writeln(e.Message);
   end;
  end;

 function ProcessDir(path:string):boolean;
  var
   sr:TSearchRec;
   r:integer;
  begin
   //if NeedExclude(path) then exit;
   writeln('Processing ',path);
   result:=true;
   r:=FindFirst(path+'\*.*',faAnyFile,sr);
   while r=0 do begin
    if sr.Name[1]='.' then begin
     r:=FindNext(sr);
     continue;
    end;
    if sr.Attr and faDirectory>0 then
      result:=result and ProcessDir(path+'\'+sr.Name)
     else
      ProcessFile(path+'\'+sr.name);
    r:=FindNext(sr); 
   end;
   FindClose(sr);
  end;

 procedure LoadExcludeList;
  var
   f:text;
   st:string;
  begin
   assign(f,'exclude');
   reset(f);
   while not eof(f) do begin
    readln(f,st);
    if length(st)>2 then
     SetLength(excludeList,length(excludelist)+1);
     excludeList[length(excludelist)-1]:=UpperCase(st);
   end;
   close(f);
  end;

begin
 try
 if paramCount=0 then begin
  writeln('Usage: CompressBuild2 dir');
  exit;
 end;
 prevName:='';
 if FileExists('exclude') then LoadExcludeList;

 fileList:='';
 assign(f,'filelist');
 rewrite(f);
 // Базовая версия
 rootdir:=GetCurrentDir+'\'+ParamStr(1);
 ProcessDir(rootDir);
 // дополнительные версии
 close(f);
 except
  on e:exception do writeln('Error: '+e.message);
 end;
end.
