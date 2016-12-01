import org.apache.hadoop.fs.FileSystem
import org.apache.spark.{SparkConf, SparkContext}
import org.apache.hadoop.fs.Path


object HdfsDeleteApp {

  def main(args: Array[String]): Unit = {
    val appID = "hdfsDeleteApp"
    val conf = new SparkConf().setMaster("local[*]").setAppName("test").set("spark.ui.enabled", "false").set("spark.app.id", appID).set("spark.driver.memory", "256m").set("spark.executor.memory", "256m").set("spark.scheduler.minRegisteredResourcesRatio", "1")
    val sc    = new SparkContext(conf)
    sc.setLogLevel("DEBUG")

    // scala> sc.hadoopConfiguration
    // res2: org.apache.hadoop.conf.Configuration = Configuration: core-default.xml, core-site.xml, mapred-default.xml, mapred-site.xml, yarn-default.xml, yarn-site.xml, hdfs-default.xml, hdfs-site.xml
    val fs = FileSystem.get(sc.hadoopConfiguration)
    val file = new Path("hello")
    println(s"exists - ${fs.exists(file)}")
    println(s"create - ${fs.create(file)}")
    println(s"exists - ${fs.exists(file)}")
    println(s"delete - ${fs.delete(file)}")
    println(s"exists - ${fs.exists(file)}")
  }
}