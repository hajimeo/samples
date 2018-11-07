from pyhive import hive
curs = hive.connect(host='node1.support.localdomain', port=10000, database='test', username='admin',
                      password='admin', auth='LDAP').cursor()
curs.execute('show tables')
print(curs.fetchall())


import jaydebeapi
curs = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                          "jdbc:hive2://node1.support.localdomain:10000/", ["admin", "admin"],
                          ["/var/tmp/share/hive-jdbc-1.0.0-standalone.jar",
                           "/var/tmp/share/hadoop-core-1.0.3.jar"]).cursor()
'''
# https://github.com/andreasnuesslein/JayDeBeApi3
curs = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                          ["jdbc:hive2://node1.support.localdomain:10000/", "admin", "admin"],
                          ["/var/tmp/share/hive-jdbc-1.0.0-standalone.jar",
                           "/var/tmp/share/hadoop-core-1.0.3.jar"]).cursor()
'''
curs.execute("show tables")
print(curs.fetchall())
