from pyhive import hive
curs = hive.connect(host='node1.support.localdomain', port=10000, database='test', username='admin',
                      password='admin', auth='LDAP').cursor()
curs.execute('show tables')
print(curs.fetchall())


import jaydebeapi
curs = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                          "jdbc:hive2://node1.support.localdomain:11111/test", ["admin", "admin"],
                          ["/var/tmp/share/atscale/hive-jdbc-1.0.0-standalone.jar",
                           "/var/tmp/share/atscale/hadoop-core-1.0.3.jar"]).cursor()
'''
# https://github.com/andreasnuesslein/JayDeBeApi3
curs = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                          ["jdbc:hive2://node1.support.localdomain:11111/Sales+Insights", "admin", "admin"],
                          ["/var/tmp/share/atscale/hive-jdbc-1.0.0-standalone.jar",
                           "/var/tmp/share/atscale/hadoop-core-1.0.3.jar"]).cursor()
'''
curs.execute("show tables")
print(curs.fetchall())
