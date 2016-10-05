'''
@author original author: Joe Young

For --deploy-mode cluster, add --jar xxx,$(echo /usr/hdp/current/spark-client/lib/datanucleus-*.jar | tr ' ' ',')
TODO: --deploy-mode cluster does not work with error "py4j.protocol.Py4JJavaError: An error occurred while calling xxx table."

Postgresql:
spark-submit --driver-class-path /usr/share/java/postgresql-9.0-801.jdbc4.jar --jars /usr/share/java/postgresql-9.0-801.jdbc4.jar \
--master yarn ./pyspark_jdbc.py "select id, case_number, primary_type, description, location_description, beat, district, ward, community_area from default.crime limit 10" "jdbc:postgresql://node1.localdomain:5432/test?searchpath=public" "org.postgresql.Driver" "public.pettytheft" postgres ********

SQL Server
spark-submit --driver-class-path /usr/share/java/sqljdbc42.jar --jars /usr/share/java/sqljdbc42.jar \
--master yarn ./pyspark_jdbc.py "select id, case_number, primary_type, description, location_description, beat, district, ward, community_area from default.crime limit 10" "jdbc:sqlserver://192.168.8.22:1433;databaseName=test" "com.microsoft.sqlserver.jdbc.SQLServerDriver" "test.dbo.pettytheft" sa ********
'''

import sys
import pprint
from pyspark import SparkConf,SparkContext
from pyspark.sql import HiveContext

# Local variables TODO: error handling
pprint.pprint(sys.argv)
_SQL      = sys.argv[1]
_JDBC     = sys.argv[2]     # 'jdbc:postgresql://172.26.73.250:5432/postgres?searchpath=public'
_DRIVER   = sys.argv[3]     # "org.postgresql.Driver"
_RDB_TBL  = sys.argv[4]
_RDB_USER = sys.argv[5]
_RDB_PWD  = sys.argv[6]
if len(sys.argv) > 7:
    _MODE  = sys.argv[7]
else:
    _MODE  = "append"


# Create a Spark Context
conf = (SparkConf()
        .setAppName("pysql_jdbc_test")
        .set("spark.dynamicAllocation.enabled","true")
        .set("spark.shuffle.service.enabled","true"))
sc = SparkContext(conf = conf)
# Create a Hive Context
hive_ctx = HiveContext(sc)

# Creating a DataFrame with sql statement
df_hive = hive_ctx.sql(_SQL)
#df_hive.cache()

# Prepare connection properties for JDBC Datasource
properties = {"user": _RDB_USER, "password": _RDB_PWD, "driver": _DRIVER}

# Write the contents of the DataFrame to the JDBC Datasource
df_hive.write.jdbc(url=_JDBC, table=_RDB_TBL, mode=_MODE, properties=properties)

'''
# How to read from Hive (from HCC article)
df = hive_ctx.load(
    source="jdbc",
    url="jdbc:sqlserver://ec2-54-244-44-6.us-west-2.compute.amazonaws.com:1433;database=sales;user=my_username;password=my_password",
    dbtable="orders")

## this is how to write to an ORC file
df.write.format("orc").save("/tmp/orc_query_output")
## this is how to write to a hive table
df.write.mode('overwrite').format('orc').saveAsTable("test_table")
'''