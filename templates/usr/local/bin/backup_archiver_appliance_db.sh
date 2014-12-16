#!/bin/bash
DATE=`date --utc "+%F %T"`

/usr/bin/mysqldump --user=<%= @mysql_username %> --password='<%= @mysql_password %>' <%= @mysql_db %> | bzip2 > "<%= @mysql_backup_dir %>/${DATE}.mysql.bz2"