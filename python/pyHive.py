from pyhive import hive
curs = hive.connect(host='node1.support.localdomain', port=10000, database='test', username='admin',
                      password='admin', auth='LDAP').cursor()
curs.execute('show tables')
print(curs.fetchall())


import jaydebeapi
curs = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                          "jdbc:hive2://node1.support.localdomain:10000/test", ["admin", "admin"],
                          ["./hive-jdbc-1.0.0-standalone.jar",
                           "./hadoop-core-1.0.3.jar"]).cursor()
curs.execute("show tables")
print(curs.fetchall())
