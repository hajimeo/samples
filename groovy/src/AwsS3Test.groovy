/*
sysPath="/opt/sonatype/nexus/system"
groovyJjar="${sysPath%/}/org/codehaus/groovy/groovy-all/2.4.17/groovy-all-2.4.17.jar"
[ -s "${groovyJjar}" ] || groovyJjar="$(find "${sysPath%/}/org/codehaus/groovy/groovy" -type f -name 'groovy-3.*.jar' 2>/dev/null | head -n1)"
java -Dgroovy.classpath="$(find ${sysPath%/}/org/sonatype/nexus/plugins/nexus-blobstore-s3 -type f -name 'nexus-blobstore-s3-*.jar' | tail -n1)" -jar "${groovyJjar}" \
    /tmp/test.groovy apac-support-bucket
 */
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.model.BucketLifecycleConfiguration;
import com.amazonaws.services.s3.model.BucketLifecycleConfiguration.Rule;
import com.amazonaws.services.s3.model.ListObjectsRequest;
import com.amazonaws.services.s3.model.ObjectListing;
import com.amazonaws.services.s3.model.lifecycle.LifecycleAndOperator;
import com.amazonaws.services.s3.model.lifecycle.LifecycleFilter;
import com.amazonaws.services.s3.model.lifecycle.LifecycleFilterPredicate;
import com.amazonaws.services.s3.model.lifecycle.LifecyclePrefixPredicate;
import com.amazonaws.services.s3.model.lifecycle.LifecycleTagPredicate

import static org.sonatype.nexus.blobstore.s3.internal.S3BlobStore.ACCESS_KEY_ID_KEY
import static org.sonatype.nexus.blobstore.s3.internal.S3BlobStore.FORCE_PATH_STYLE_KEY
import static org.sonatype.nexus.blobstore.s3.internal.S3BlobStore.REGION_KEY
import static org.sonatype.nexus.blobstore.s3.internal.S3BlobStore.SECRET_ACCESS_KEY_KEY
import static org.sonatype.nexus.blobstore.s3.internal.S3BlobStore.SIGNERTYPE_KEY;

def main(String[] args) {
    def p = System.getenv() // AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

    String accessKeyId = p.AWS_ACCESS_KEY_ID
    String secretAccessKey = p.AWS_SECRET_ACCESS_KEY
    String region = p.AWS_REGION
    S3Client s3 = S3Client.builder()
            .region(Region.of(p.AWS_REGION)) // Specify your AWS region
            .build()
    String bucketName = args[0]

    try {
        // Retrieve the bucket policy
        GetBucketPolicyResponse response = s3.getBucketPolicy(GetBucketPolicyRequest.builder().bucket(bucketName).build())
        println(response.policy())
    } catch (Exception e) {
        // Handle exceptions
        System.err.println("Error retrieving bucket policy: " + e.message())
    } finally {
        // Close the S3 client
        s3.close()
    }
}

main(args)