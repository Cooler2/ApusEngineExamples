unit globals;
interface
 uses windows,ControlFiles2,MyServis,logging;
const
 MAX_CONNECTIONS_LIMIT = 20000;
 MAX_WORKERS           = 10;
 MAX_USERS             = 2000;

 MINUTE =  1/1440;
 SECOND =  1/86400;

type
  TMimeType=record
   extension:UTF8String;
   mimeType:UTF8String;
  end;

  // Если имя запрашиваемого стат. файла содержит pattern, то при выдаче этого файла будет указано данное значение cache-control 
  TCacheControl=record
   pattern:UTF8String;
   value:UTF8String;
  end;

  TServerStat=record
   // Счётчики статистических величин на заданную дату
   sentBytes,  // сетевой трафик
   recvBytes,
   httpConnections,   // кол-во установленных соединений,
   httpRequests,   // обработанных запросов
   httpErrors,  // кол-во запросов, на которые отвечено ошибкой
   authErrors, // кол-во ошибок авторизации
   tasks,       // кол-во выполненных тасков
   dbQueries,   // кол-во выполненных запросов к БД
   dbFailures,   // кол-во сбоев при обращении к БД
   failures,      // кол-во сбоев (записей в лог соответствующего типа)
   logMessages,   // кол-во записей в лог (всех уровней)
   duelsStarted,  // кол-во запущеных боёв
   draftsStarted, // кол-во стартованых драфтов
   publicMsg,     // кол-во отправленных публичных сообщений в чате
   privMsg,       // кол-во приватных сообщений в чате
   ipBanned,      // назначенные баны по IP
   connDenied,    // отклонённые подключения по причине бана IP
   connBroken,    // дисконнектов (неправильных логаутов)
   gdUpdates,     // апдейтов на уровне GD
     res:int64;
   // Моментальные значения
   connections, // кол-во установленных соединений
   users,      // кол-во юзеров (включая ботов)
   usersAlive, // кол-во живых юзеров
   duels,      // кол-во боёв
   drafts,     // кол-во драфтов
   cpuUsageKernel, // загруженность процессора сервером, время в ms
   cpuUsageUser,  // загруженность процессора сервером, время в ms
   cpuTotal,   // загруженность процессора (общесистемная)
   maxQueue,   // макс размер очереди тасков
   memoryUsed, // сколько памяти использует сервер
    res2:integer;
  end;


 TServerState=(ssStarting,ssFailure,ssRunning,ssLimited,ssClosing,ssRestarting);

var
 // Здесь хранится вся актуальная статистика по серверу
 // Эта структура загружается из БД при старте сервера и затем постоянно обновляется
 serverStat:TServerStat;

 MAX_CONNECTIONS:integer = 6000; // up to MAX_CONNECTIONS_LIMIT

 INBUF_SIZE:integer = 40000; // размер буфера входящих данных (макс. размер запроса, не должен быть меньше 4К)
 REQUEST_TIMEOUT:integer = 5000; // 5 секунд - если запрос не поступает за такое время, соединение закрывается
 KEEP_ALIVE_TIMEOUT:integer = 40000; // 40 секунд держать открытым keep alive соединение после отправки ответа
 DATA_TIMEOUT:integer = 20000; // ждать поступления comet-данных 20 секунд
 USER_TIMEOUT:integer = 35000; // время неактивности юзера, после которого он удаляется по таймауту
 NET_LOOP_INTERVAL:integer = 10;  // определяет скорость работы сетевого цикла и связанные с ней задержки
 HTTP_PORT:integer = 80;
 MAX_LOCAL_FILESIZE:integer = 2048*1024; // максимальный размер файлов, отдаваемых сервером (2048 KB)

 NUM_WORKERS:integer = 3;  // кол-во потоков, обрабатывающих "длинные" запросы

 MAX_URGENCY:integer = 2;

 SEND_ACAO:boolean=false; // Access-Control-Allow-Origin

 SPARE_SERVER:boolean=false;

 STEAM_API_KEY:UTF8String='';

 LOG_VERBOSITY:byte=logImportant; // minimal level to write to file
 LOG_FLUSH_INTERVAL:byte=50;  // периодичность записи в лог (в периодах главного цикла (1-10 мс))
 // Что нужно подробно логировать
 LOG_HTTP:boolean=false; // log HTTP requests and responses
 LOG_SQL:boolean=false; // Log all SQL queries
 LOG_TASKS:boolean=false; 

 SERVER_NAME:UTF8String='ApusServer';

 MySQL_HOST:UTF8String='127.0.0.1';
 MySQL_DATABASE:UTF8String='';
 MySQL_LOGIN:UTF8String='';
 MySQL_PASSWORD:UTF8String='';

 serviceMode:boolean=true;
 WorkingDir:UTF8String;
 needExit:boolean=false;
 ctl:TControlFile;

 accessToken,controlToken:UTF8String;

 homeDir:UTF8String; // путь к статическим файлам
 MimeTypes:array of TMimeType; 
 cacheRules:array of TCacheControl;

 // Время ожидания (сек) юзера в автопоиске после которого добавляется подходящий бот
 BOT_DELAY_CLASSIC:integer=15;
 BOT_DELAY_CUSTOM:integer=15;
 BOT_DELAY_DRAFT:integer=15;

 BOT_TURN_DELAY:integer=1;
 BOT_ACTION_DELAY:integer=1;

 serverState:TServerState=ssStarting;
 restartTime:TDateTime; // когда запланирован рестарт
 restartNotices:integer; // кол-во отправленных уведомлений
 welcomeEn,welcomeRu,altWelcomeEn,altWelcomeRu:UTF8String;
 altWelcomeForDate:TDateTime;

 chatFilter:WStringArr; // список слов, которые заменяются на *** в чате

 // доступ ко всем глобальным переменным во всех модулях (кроме защищенных по-иному)
 // должен осуществляться только внутри этой секции
 gSect:TMyCriticalSection;

 // HTML templates
 loginPage,adminPage:UTF8String;

 // Currently processed user request
 curUser:integer;
 curUserCmd:UTF8String;

 function ShortMD5(st:UTF8String):UTF8String;

implementation
 uses SysUtils,DCPmd5a;

 function ShortMD5(st:UTF8String):UTF8String;
  begin
   result:=MD5(st);
   setLength(result,10);
  end;

{ TCustomMySQLDatabase }

initialization
 InitCritSect(gSect,'Global',20);
finalization
 DeleteCritSect(gSect);
end.
