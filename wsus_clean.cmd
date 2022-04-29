net stop wuauserv

net stop bits

net stop cryptsvc

ren %systemroot%\SoftwareDistribution sdold123

ren %systemroot%\System32\catroot2 cr2old123

net start cryptsvc

net start bits

net start wuauserv