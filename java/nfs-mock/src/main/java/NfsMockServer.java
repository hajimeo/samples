import org.dcache.nfs.vfs.VirtualFileSystem;
import org.dcache.nfs.ExportFile;

public class NfsMockServer {
    public static void main(String[] args) throws Exception {

        // create an instance of a filesystem to be exported
        VirtualFileSystem vfs = new ....;

        // create the RPC service which will handle NFS requests
        OncRpcSvc nfsSvc = new OncRpcSvcBuilder()
                .withPort(2049)
                .withTCP()
                .withAutoPublish()
                .withWorkerThreadIoStrategy()
                .build();

        // specify file with export entries
        ExportFile exportFile = new ExportFile(....);

        // create NFS v4.1 server
        NFSServerV41 nfs4 = new NFSServerV41.Builder()
                .withExportFile(exportFile)
                .withVfs(vfs)
                .withOperationFactory(new MDSOperationFactory())
                .build();

        // create NFS v3 and mountd servers
        NfsServerV3 nfs3 = new NfsServerV3(exportFile, vfs);
        MountServer mountd = new MountServer(exportFile, vfs);

        // register NFS servers at portmap service
        nfsSvc.register(new OncRpcProgram(100003, 4), nfs4);
        nfsSvc.register(new OncRpcProgram(100003, 3), nfs3);
        nfsSvc.register(new OncRpcProgram(100005, 3), mountd);

        // start RPC service
        nfsSvc.start();

        System.in.read();
    }
}
