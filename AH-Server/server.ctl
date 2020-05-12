
ServiceName "AHserver"
DisplayName "AHserver"

# If this value is greater than cnsts.version, then this value is used insted
# cnsts.sVesrion is autoupdated too
UpdateVersion 1012

# Password to access admin/management area (used as cookie)
AccessToken  "ACCESSTOKEN"
# Password to perform admin actions
ControlToken "TOKEN"

SteamAPIkey  ""

# Number of worker threads (1..10)
NumWorkers  2

# Urgency threshold to wake-up network thread immediately
MaxUrgency  2

# Base process priority: "Normal" or "Above normal" (not implemented)
BasePriority "Normal"

# Map unhandled HTTP-requests to this directory
HomeDir "e:\web\GameServ"

# Does not update global stats etc.
SpareServer OFF

$Section Net
  Port           2993
  MaxConnections 2000

  # Close connection if no request received within this period (sec)
  RequestTimeout 5

  # Keep connection alive for this period (sec)
  KeepAliveTimeout 40
  # Interval to wait for user data (COMET period, sec)
  DataTimeout 20

  # Max user inactivity time (sec)
  UserTimeout 40

  # Buffer size for incoming requests (bytes)
  InBufSize 32000

  # How often it should process requests, accept connections etc... (ms)
  NetLoopInterval 5

  # Include Access-Control-Allow-Origin header (for cross-domain requests)
  SendACAO  No
$EndOfSection

$Section CacheControl
  $Section Images
    Pattern  "/img/"
    Value    "max-age=864000"
  $EndOfSection
$EndOfSection

$Section Mime
  $Section html
    Type     "text/html"
    Extensions ".htm .html"
  $EndOfSection

  $Section Javascript
    Type     "application/x-javascript"
    Extensions ".js"
  $EndOfSection

  $Section CSS
    Type     "text/css"
    Extensions ".css"
  $EndOfSection

  $Section JPEG
    Type     "image/jpeg"
    Extensions ".jpg .jpeg"
  $EndOfSection

  $Section GIF
    Type     "image/gif"
    Extensions ".gif"
  $EndOfSection

  $Section PNG
    Type     "image/png"
    Extensions ".png"
  $EndOfSection
$EndOfSection

$Section Log
  # In-memory logging buffer size (MB)
  LogSize 64

  # Flush log every X seconds
  FlushInterval 30

  # Verbosity - minimal level to write messages to log file (all messages are stored in memory)
  Verbosity 0

  LogHTTP yes
  LogSQL yes
$EndOfSection

$Section MySQL
  Host          "localhost"
  Login         "mysql_user"
  Password      "mysql_password"
  Database      "db_name"
$EndOfSection

$Section Welcome
  En        "Welcome to the Astral Heroes League! Please be kind and polite! http://astralheroes.com/abc?id=123"
  AltEn     "Game updated: now you can buy some gold! :-) http://astralheroes.com/abc?id=123"
  Ru        "Добро пожаловать в Лигу! Будьте вежливы с другими игроками!"
  AltRu     "Игра обновлена: теперь вы можете купить золото или премиум! :-)"
  AltForDate "2016-04-02 20:00"
$EndOfSection

$Section Game
  # Add bot for players who wait longer than X sec
  BotDelayCustom   3
  BotDelayClassic  3
  BotDelayDraft    3

  # Delay (sec) after bots turn started
  BotTurnDelay     1
  # Delay (sec) between bots actions
  BotActionDelay   1

$EndOfSection