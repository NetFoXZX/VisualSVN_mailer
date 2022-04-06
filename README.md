# VisualSVN mailer
Скрипт персонализированной почтовой рассылки об изменениях в конкретных объектах (каталоги\файлы) в репозиториях VisualSVN

## Особенности
- Возможность назначить нескольких получателей на конкретный объект в репозитории
- Исключение дублирования писем одному получателю, если он назначен но объекты вложенные друг в друга
- Работает на верисях VisulSVN Server ниже 4.х (в которых еще не было PS модуля управления)
- Получает почтовый адрес автора из Active Directory
- Формирование HTML кода, пригодного для отправки по почте или на frontend
