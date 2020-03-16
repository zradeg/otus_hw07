# Инициализация системы. Systemd и SysV

## Задачи
1. Создать сервис и unit-файлы для этого сервиса:
- сервис: bash, python или другой скрипт, который мониторит log-файл на наличие ключевого слова;
- ключевое слово и путь к log-файлу должны браться из /etc/sysconfig/ (.service);
- сервис должен активироваться раз в 30 секунд (.timer).
2. Дополнить unit-файл сервиса httpd возможностью запустить несколько экземпляров сервиса с разными конфигурационными файлами
3. Создать unit-файл(ы) для сервиса:
- сервис: скрипт с exit 143;
- ограничить сервис по использованию памяти;
- ограничить сервис ещё по трём ресурсам, которые не были рассмотрены на лекции;
- реализовать один из вариантов restart и объяснить почему выбран именно этот вариант.

## 1. Создание сервиса и unit-файла для него
Создаем конфигурационный файл для сервиса:
```
[root@hw07-systemd ~] cat > /etc/sysconfig/watchlog
# Configuration file for my watchlog service
# Place it to /etc/sysconfig
# File and word in that file that we will be monit
WORD="ALERT"
LOG=/var/log/watchlog.log
```
Создаю лог-файл на случай, если ниже созданное задание в crontab отработает позже создаваемого сервиса:
```
[root@hw07-systemd ~] > /var/log/watchlog.log
```
Создаю скрипты для пополнения лога:
```
[root@hw07-systemd ~]# cat > /opt/alert_add.sh
#!/bin/bash
/bin/echo `/bin/date "+%b %d %T"` ALERT >> /var/log/watchlog.log

[root@hw07-systemd ~]# cat /opt/tail_add.sh
#!/bin/bash
/bin/tail /var/log/messages >> /var/log/watchlog.log

[root@hw07-systemd ~]# chmod +x /opt/tail_add.sh /opt/alert_add.sh
```


Создаю задания в crontab:
```
[root@hw07-systemd ~] crontab -e
*/3  *  *  *  * /opt/tail_add.sh
*/5  *  *  *  * /opt/alert_add.sh
```

Создаю непосредственно скрипт, который будет выполняться в ходе работы сервиса:
```
[root@hw07-systemd ~] cat > /opt/watchlog.sh
#!/bin/bash
WORD=$1
LOG=$2
DATE=`/bin/date`
if grep $WORD $LOG &> /dev/null; then
    logger "$DATE: I found word, Master!"
	exit 0
else
    exit 0
fi
```

Добавляю скрипту бит исполнения:
```
[root@hw07-systemd ~] chmod +x /opt/watchlog.sh
```
Формирую unit-файл сервиса:
```
[root@hw07-systemd ~] cat > /etc/systemd/system/watchlog.service
[Unit]
Description=My watchlog service

[Service]
Type=oneshot
EnvironmentFile=/etc/sysconfig/watchlog
ExecStart=/opt/watchlog.sh $WORD $LOG
```

Формирую unit-файл таймера:
```
[root@hw07-systemd ~] cat > /etc/systemd/system/watchlog.timer
[Unit]
Description=Run watchlog script every 30 second

[Timer]
# Run every 30 second
OnUnitActiveSec=30
Unit=watchlog.service

[Install]
WantedBy=multi-user.target
```

Обновляю информацию о юнитах:
```
[root@hw07-systemd ~] systemctl daemon-reload
```

Запускаю юнит:
```
[root@hw07-systemd ~] systemctl start watchlog
[root@hw07-systemd ~] systemctl enable watchlog
```

Проверяю:
```
[root@hw07-systemd ~] tail -f /var/log/messages
Mar 15 15:06:20 hw07-systemd systemd: Starting My watchlog service...
Mar 15 15:06:20 hw07-systemd root: Sun Mar 15 15:06:20 UTC 2020: I found word, Master!
Mar 15 15:06:20 hw07-systemd systemd: Started My watchlog service.
Mar 15 15:06:20 hw07-systemd systemd: Stopped Run watchlog script every 30 second.
Mar 15 15:06:26 hw07-systemd systemd: Started Run watchlog script every 30 second.
```

## 2. Дополнить unit-файл сервиса httpd возможностью запустить несколько экземпляров сервиса с разными конфигурационными файлами.

Создаю первый юнит-файл:
```
[root@hw07-systemd ~]# cat > /etc/systemd/system/httpd@first.service
[Unit]
Description=The Apache HTTP Server
After=network.target remote-fs.target nss-lookup.target
Documentation=man:httpd(8)
Documentation=man:apachectl(8)

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/httpd-%I
ExecStart=/usr/sbin/httpd $OPTIONS -DFOREGROUND
ExecReload=/usr/sbin/httpd $OPTIONS -k graceful
ExecStop=/bin/kill -WINCH ${MAINPID}
# We want systemd to give httpd some time to finish gracefully, but still want
# it to kill httpd after TimeoutStopSec if something went wrong during the
# graceful stop. Normally, Systemd sends SIGTERM signal right after the
# ExecStop, which would kill httpd. We are sending useless SIGCONT here to give
# httpd time to finish.
KillSignal=SIGCONT
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```
Создаю второй юнит-файл:
```
[root@hw07-systemd ~]# cat /etc/systemd/system/httpd@second.service
[Unit]
Description=The Apache HTTP Server
After=network.target remote-fs.target nss-lookup.target
Documentation=man:httpd(8)
Documentation=man:apachectl(8)

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/httpd-%I
ExecStart=/usr/sbin/httpd $OPTIONS -DFOREGROUND
ExecReload=/usr/sbin/httpd $OPTIONS -k graceful
ExecStop=/bin/kill -WINCH ${MAINPID}
# We want systemd to give httpd some time to finish gracefully, but still want
# it to kill httpd after TimeoutStopSec if something went wrong during the
# graceful stop. Normally, Systemd sends SIGTERM signal right after the
# ExecStop, which would kill httpd. We are sending useless SIGCONT here to give
# httpd time to finish.
KillSignal=SIGCONT
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Конфиги для первого и второго юнита:
```
[root@hw07-systemd ~]# grep -P "^OPTIONS" /etc/sysconfig/httpd-first
OPTIONS=-f conf/first.conf

[root@hw07-systemd ~]# grep -P "^OPTIONS" /etc/sysconfig/httpd-second
OPTIONS=-f conf/second.conf
```

Настройки pid-файла и прослушиваемого порта в конфиге для первого и второго юнитов:
```
[root@hw07-systemd ~]# grep -P "^PidFile|^Listen" /etc/httpd/conf/first.conf
PidFile "/var/run/httpd-first.pid"
Listen 80
[root@hw07-systemd ~]# grep -P "^PidFile|^Listen" /etc/httpd/conf/second.conf
PidFile "/var/run/httpd-second.pid"
Listen 8080
```

Поочередно запускаем юниты:
```
[root@hw07-systemd ~]# systemctl start httpd@first
[root@hw07-systemd ~]# systemctl start httpd@second
```

Проверяем результат:
```
[root@hw07-systemd ~]# ss -tunlp | grep httpd
tcp    LISTEN     0      128      :::8080                 :::*                   users:(("httpd",pid=19603,fd=4),("httpd",pid=19602,fd=4),("httpd",pid=19601,fd=4),("httpd",pid=19600,fd=4),("httpd",pid=19599,fd=4),("httpd",pid=19598,fd=4))
tcp    LISTEN     0      128      :::80                   :::*                   users:(("httpd",pid=19591,fd=4),("httpd",pid=19590,fd=4),("httpd",pid=19589,fd=4),("httpd",pid=19588,fd=4),("httpd",pid=19587,fd=4),("httpd",pid=19586,fd=4))
```

## 3. Настройки для unit-файла
Воспользуюсь уже созданным скриптом watchlog.sh.
Модифицирую его код выхода:
```
[root@hw07-systemd ~]sed -i 's/exit 0/exit 143/' /opt/watchlog.sh
```

Добавлю в секцию [Service] unit-файла сервиса следующие строки:
```
[root@hw07-systemd ~]# cat >> /etc/systemd/system/watchlog.service
MemoryLimit=50M #ограничение используемой памяти сервисом - 50Мб
LimitCPU=29		#ограничение процессорного времени до 29 секунд
LimitNPROC=1	#ограничение количества процессов
LimitNICE=-1	#ограничение nice сервиса

SuccessExitStatus=143	#установка специфичного кода выхода
Restart=on-abort		#условия для рестарта сервиса
```

Даю команду перечитать юниты:
```
[root@hw07-systemd ~]# 
```

Restart=on-abort выбран, т.к. он учитывает вероятность снятия задачи пользователем командой kill. Какие-либо еще варианты сбоя маловероятны ввиду простоты скрипта.
