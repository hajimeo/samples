#!/usr/bin/env bash
#
# Based on https://gist.github.com/rajkrrsingh/24ff6f426248276cfa79063967f08213
#

echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] INFO: generating dummy csv files..."
wget -nv -c -t 2 --timeout=10 --waitretry=3 https://raw.githubusercontent.com/hajimeo/samples/master/misc/sample_07.csv -O sample_07.csv
wget -nv -c -t 2 --timeout=10 --waitretry=3 https://raw.githubusercontent.com/hajimeo/samples/master/misc/sample_08.csv -O sample_08.csv
wget -nv -c -t 2 --timeout=10 --waitretry=3 https://raw.githubusercontent.com/hajimeo/samples/master/misc/census.csv -O census.csv
echo '101,Kyle,Admin,50000,A
102,Xander,Admin,50000,B
103,Jerome,Sales,60000,A
104,Upton,Admin,50000,C
105,Ferris,Admin,50000,C
106,Stewart,Tech,12000,A
107,Chase,Tech,12000,B
108,Malik,Engineer,45000,B
109,Samson,Admin,50000,A
110,Quinlan,Manager,40000,A
111,Joseph,Manager,40000,B
112,Axel,Sales,60000,B
113,Robert,Manager,40000,A
114,Cairo,Engineer,45000,A
115,Gavin,Ceo,100000,D
116,Vaughan,Manager,40000,B
117,Drew,Engineer,45000,D
118,Quinlan,Admin,50000,B
119,Gabriel,Engineer,45000,A
120,Palmer,Ceo,100000,A' > ./employee.csv

echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] INFO: executing hive queries... kinit may require"
hive -e "
set hive.tez.exec.print.summary;
CREATE DATABASE IF NOT EXISTS dummies;
USE dummies;
CREATE TABLE IF NOT EXISTS sample_07 (
  code string,
  description string,
  total_emp int,
  salary int )
  ROW FORMAT DELIMITED
  FIELDS TERMINATED BY '\t'
  STORED AS TextFile;
load data local inpath './sample_07.csv' OVERWRITE into table sample_07;
create table sample_07_orc stored as orc  as select * from sample_07;
CREATE TABLE IF NOT EXISTS sample_08 (
  code string ,
  description string ,
  total_emp int ,
  salary int )
  ROW FORMAT DELIMITED
  FIELDS TERMINATED BY '\t'
  STORED AS TextFile;
load data local inpath './sample_08.csv' OVERWRITE into table sample_08;
create external IF NOT EXISTS table emp_stage (
  empid int,
  name string,
  designation  string,
  Salary int,
  department string)
  row format delimited
  fields terminated by ","
  location '/tmp/emp_stage_data';
load data local inpath './employee.csv' OVERWRITE into table emp_stage;
set hive.exec.dynamic.partition=true
set hive.exec.dynamic.partition.mode=nonstrict;
-- set hive.exec.max.dynamic.partitions.pernode=4;
-- set hive.exec.max.created.files=100000;
create table IF NOT EXISTS emp_part_dy (
    empid int,
    name string,
    designation  string,
    salary int)
    PARTITIONED BY (department String)
    row format delimited fields terminated by ',';
INSERT OVERWRITE TABLE emp_part_dy PARTITION(department) SELECT empid, name,designation,salary,department FROM emp_stage;
create table IF NOT EXISTS census(
ssn int,
name string,
city string,
email string)
row format delimited
fields terminated by ',';
load data local inpath '/tmp/census.csv' OVERWRITE into table census;
create table IF NOT EXISTS census_clus(
ssn int,
name string,
city string,
email string)
clustered by (ssn) into 8 buckets;
set hive.enforce.bucketing=true
insert overwrite table census_clus select * from census;
"
# create table sample_07_id like sample_07; -- to create an identical table
# select INPUT__FILE__NAME, code from sample_08;
# select INPUT__FILE__NAME,empid from default.emp_part_dy where department='D';


