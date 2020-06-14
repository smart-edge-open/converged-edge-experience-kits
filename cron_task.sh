#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019-2020 Intel Corporation

exec &> /var/log/cron_task.log

cron_IPscript=$(crontab -l | grep IPchange.sh)
if [ "$cron_IPscript" != "" ]
then
        echo "Cron script entry exists."
else
        crontab -l > mycron
        echo "@reboot /opt/controller_ip/IPchange.sh" >> mycron
        crontab mycron
        rm mycron
fi


cron_task_script=$(crontab -l | grep cron_task.sh)
if [ "$cron_task_script" != "" ]
then
        echo "Cron task entry exists."
else
        crontab -l > mycron
        echo "* * * * * /opt/controller_ip/cron_task.sh" >> mycron
        crontab mycron
        rm mycron
fi



check_IPchange=$(ps -ef|grep IPchange.sh|awk '/bash/ {print $2}')
words=$(wc -w <<< "$check_IPchange")
if [ "$words" -gt 1 ]
then
	kill -9 $check_IPchange
	/opt/controller_ip/IPchange.sh &
	echo "Killed $words instances. Started the script..."
elif [ "$words" -eq 1 ]
then
	echo "Dynamic Controller IP change feature is running..."
else
	/opt/controller_ip/IPchange.sh &
	echo "IPchange script started"
fi

