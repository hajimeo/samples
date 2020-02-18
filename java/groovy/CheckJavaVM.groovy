// https://gist.github.com/rednaxelafx/1388046

package groovy

import java.lang.management.ManagementFactory
import com.sun.tools.attach.VirtualMachine
import com.codahale.metrics.jvm.ThreadDump

name = ManagementFactory.runtimeMXBean.name
vmid = name[0..<name.indexOf('@')]
vm = VirtualMachine.attach(vmid)
tmxbean = ManagementFactory.getThreadMXBean();

def heapHisto(vm) {
  //histo = vm.heapHisto("-live").text  # This hangs and '[{"-live"}]' does not work.
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

hist_string = heapHisto(vm)
threads_string = threadDump(tmxbean)