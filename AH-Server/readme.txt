How to run the game server:

* Build the executable.

* Make sure you have a MySQL database (template is in AH-Site project)

* Edit server.ctl file: at least put a valid MySQL user/password to access the DB
  and set access tokens to access the admin page

* It can run either as a service or as a regular process:
  "ahserver --install" - install the service
  "ahserver --uninstall" - remove the service
  "ahserver -run" - just run as a regular process

* When running, you can access the admin pages:
  127.0.0.1:2993/admin - server management page
  127.0.0.1:2993/log - view/manage server logs (logs are stored in "Logs" folder and kept in memory)

* Graceful shutdown. Either:
  - stop the service
  - shutdown via the admin page
  - put "command.txt" file with "STOP" phrase (it will be automatically deleted)

* See "AM2Protocol.txt.docx" for the client-server protocol specfication.