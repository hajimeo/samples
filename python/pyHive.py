from pyhive import hive

host_name = "atscale720"
port = 10000
user = "hive"
password = "hive"
database="default"

def hiveconnection(host_name, port, user,password, database):
    conn = hive.Connection(host=host_name, port=port, username=user, password=password,
                           database=database, auth='CUSTOM')
    cur = conn.cursor()
    cur.execute('show tables')
    result = cur.fetchall()
    return result

# Call above function
output = hiveconnection(host_name, port, user,password, database)
print(output)






















curs = hive.connect(host='node1.support.localdomain', port=10000, database='test', username='admin',
                      password='admin', auth='LDAP').cursor()
curs.execute('show tables')
print(curs.fetchall())

import sqlalchemy
def conn():
    return connect(host='atscale720',
                   port=11111,
                   database='Sales+Insights',
                   timeout=20,
                   user='admin', password='admin',
                   auth_mechanism='PLAIN')

engine = sqlalchemy.create_engine('hive://', creator=conn)

db = sqlalchemy.create_engine('hive://')


import jaydebeapi
curs = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                          "jdbc:hive2://atscale720:11111/", ["admin", "admin"],
                          ["/Users/hajime/Desktop/hive-jdbc-1.0.0-standalone.jar",
                           "/Users/hajime/Desktop/hadoop-core-1.0.3.jar"]).cursor()
'''
# https://github.com/andreasnuesslein/JayDeBeApi3
curs = jaydebeapi.connect("org.apache.hive.jdbc.HiveDriver",
                          ["jdbc:hive2://atscale720:10000/", "admin", "admin"],
                          ["/var/tmp/share/hive-jdbc-1.0.0-standalone.jar",
                           "/var/tmp/share/hadoop-core-1.0.3.jar"]).cursor()
'''
curs.execute("show tables")
print(curs.fetchall())
