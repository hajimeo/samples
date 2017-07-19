import sys
sys.path=sys.path + ['/usr/lib/python2.6/site-packages','/usr/lib/python2.6/site-packages/resource_monitoring/psutil','/usr/lib/python2.6/site-packages/resource_monitoring/psutil/build/lib.linux-x86_64-2.6']
import psutil

def get_mem_info():
    """
    Return memory statistics at current time
    """

    mem_stats = psutil.virtual_memory()
    swap_stats = psutil.swap_memory()
    mem_total = get_host_static_info().get('mem_total')
    swap_total = get_host_static_info().get('swap_total')

    bytes2kilobytes = lambda x: x / 1024

    return {
        'mem_total': bytes2kilobytes(mem_total) if mem_total else 0,
        'mem_used': bytes2kilobytes(mem_stats.used - mem_stats.cached) if hasattr(mem_stats, 'used') and hasattr(mem_stats, 'cached') else 0, # Used memory w/o cached
        'mem_free': bytes2kilobytes(mem_stats.available) if hasattr(mem_stats, 'available') else 0, # the actual amount of available memory
        'mem_shared': bytes2kilobytes(mem_stats.shared) if hasattr(mem_stats, 'shared') else 0,
        'mem_buffered': bytes2kilobytes(mem_stats.buffers) if hasattr(mem_stats, 'buffers') else 0,
        'mem_cached': bytes2kilobytes(mem_stats.cached) if hasattr(mem_stats, 'cached') else 0,
        'swap_free': bytes2kilobytes(swap_stats.free) if hasattr(swap_stats, 'free') else 0,
        'swap_used': bytes2kilobytes(swap_stats.used) if hasattr(swap_stats, 'used') else 0,
        'swap_total': bytes2kilobytes(swap_total) if swap_total else 0,
        'swap_in': bytes2kilobytes(swap_stats.sin) if hasattr(swap_stats, 'sin') else 0,
        'swap_out': bytes2kilobytes(swap_stats.sout) if hasattr(swap_stats, 'sout') else 0,
        # todo: cannot send string
        #'part_max_used' : disk_usage.get("max_part_used")[0],
    }

def get_host_static_info():

    boot_time = psutil.boot_time()
    cpu_count_logical = psutil.cpu_count()
    swap_stats = psutil.swap_memory()
    mem_info = psutil.virtual_memory()

    # No ability to store strings
    return {
      'cpu_num' : cpu_count_logical,
      'swap_total' : swap_stats.total,
      'boottime' : boot_time,
      # 'machine_type' : platform.processor(),
      # 'os_name' : platform.system(),
      # 'os_release' : platform.release(),
      'mem_total' : mem_info.total
    }

if __name__ == '__main__':
    print get_mem_info()