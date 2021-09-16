import java.nio.file.FileSystems;

def fs = FileSystems.getDefault();
for (def s : fs.getFileStores()) {
  print("$s\n")
  def total_kb = s.getTotalSpace() / 1024;
  def usable_kb = s.getUsableSpace() / 1024;
  print("    $usable_kb / $total_kb KB\n")
}