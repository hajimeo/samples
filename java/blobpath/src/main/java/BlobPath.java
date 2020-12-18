import java.io.*; 
  
class BlobPath {
    public static void main(String[] args) 
    { 
        String blobId = args[0];
        int hc = blobId.hashCode();
        int t1 = Math.abs(hc % 43) + 1;
        int t2 = Math.abs(hc % 47) + 1;
        System.out.printf("vol-%02d/chap-%02d/%s%n", t1, t2, blobId);
    }
} 