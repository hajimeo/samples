// https://gist.github.com/rednaxelafx/1388046

package groovy

import java.lang.management.ManagementFactory
import com.sun.tools.attach.VirtualMachine
import com.codahale.metrics.jvm.ThreadDump

def vmid = ManagementFactory.runtimeMXBean.name[0..<name.indexOf('@')]
def vm = VirtualMachine.attach(vmid)
def tmxbean = ManagementFactory.getThreadMXBean();

def heapHisto(vm) {
  histo = vm.heapHisto().text
  vm.detach()
  return histo
}

def threadDump(tmxbean) {
  // Using org.sonatype.nexus.internal.atlas.customizers.MetricsCustomizer
  threadDump = new ThreadDump(tmxbean)
  out = new ByteArrayOutputStream();
  threadDump.dump(out)
  return out
}

def hist_string = heapHisto(vm)
def threads_string = threadDump(tmxbean)