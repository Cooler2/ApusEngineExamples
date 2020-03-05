Steps to launch the site.

1. Create a MySQL database using the "database.sql" script
2. Edit "config.ctl" file: set proper DB name/login/password. Edit also the site (frontend) folder.
3. Configure Nginx to work with SCGI server, see nginx.conf file
4. Build "Website.dpr" and run it.

Please note: some features will not work because of different dependencies!