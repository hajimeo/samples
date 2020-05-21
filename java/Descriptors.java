//https://github.com/srisatish/openjdk/blob/master/jdk/test/com/sun/management/UnixOperatingSystemMXBean/GetMaxFileDescriptorCount.java

import com.sun.management.UnixOperatingSystemMXBean;

import java.lang.management.*;

class Descriptors
{
  private static UnixOperatingSystemMXBean mbean =
      (UnixOperatingSystemMXBean) ManagementFactory.getOperatingSystemMXBean();

  public static void main(String args[]) {
    try {
      long current_count = mbean.getOpenFileDescriptorCount();
      long max_count = mbean.getMaxFileDescriptorCount(); // Is this hard limit?
      System.out.println(current_count + "/" + max_count);
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }
}