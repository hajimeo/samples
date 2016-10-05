'''
@author original author: Joe Young

spark-submit --jars /usr/share/java/postgresql-9.0-801.jdbc4.jar --driver-class-path /usr/share/java/postgresql-9.0-801.jdbc4.jar --master local ./pyspark_jdbc.py "select id, case_number, primary_type, description, location_description, beat, district, ward, community_area from crime limit 10" "jdbc:postgresql://node1.localdomain:5432/test?searchpath=public" "org.postgresql.Driver" "public.pettytheft" ambari bigdata
'''
import sys
from pyspark import SparkConf,SparkContext
from pyspark.sql import HiveContext

# Local variables TODO: error handling
_SQL      = sys.argv[1]
_JDBC     = sys.argv[2]     # 'jdbc:postgresql://172.26.73.250:5432/postgres?searchpath=public'
_DRIVER   = sys.argv[3]     # "org.postgresql.Driver"
_RDB_TBL  = sys.argv[4]
_RDB_USER = sys.argv[5]
_RDB_PWD  = sys.argv[6]

# Create a Spark Context
conf = (SparkConf()
        .setAppName("pysql_jdbc_test")
        .set("spark.dynamicAllocation.enabled","true")
        .set("spark.shuffle.service.enabled","true"))
sc = SparkContext(conf = conf)
# Create a Hive Context
hive_ctx = HiveContext(sc)

# SQL can be run over DataFrames that have been registered as a table.
df_hive = hive_ctx.sql(_SQL)
#df_hive.cache()

# Prepare connection properties for JDBC Datasource
properties = {"user": _RDB_USER, "password": _RDB_PWD, "driver": _DRIVER}

# Write the contents of the DataFrame to the JDBC Datasource
df_hive.write.jdbc(url=_JDBC, table=_RDB_TBL, mode='overwrite', properties=properties)

print "Exiting..."

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