/*
 For jrunscript -e "var fis = new java.io.FileInputStream('$file');var dis = new java.security.DigestInputStream(fis, java.security.MessageDigest.getInstance('SHA-512'));var z = new java.util.zip.ZipInputStream(dis);print(z.available());"
 */
var fis = new java.io.FileInputStream('./AesCts/1.0.0/AesCts-1.0.0.nupkg');
//var ba = javaByteArray(64);
var dis = new java.security.DigestInputStream(fis, java.security.MessageDigest.getInstance('SHA-512'));
//var bis = new java.io.BufferedInputStream(fis);
var z = new java.util.zip.ZipInputStream(dis);
print(z.available());
//for(var zp in z) print(zp, typeof z[zp]);
