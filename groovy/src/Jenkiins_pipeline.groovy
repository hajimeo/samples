pipeline {
    agent any
    stages {
        stage('iq-cli-exe') {
            steps {
                script {
                    def cmd = "/usr/local/bin/nexus-iq-cli -s http://dh1:8070/ -a admin:admin123 -i sandbox-application -t build /Volumes/Samsung_T5/hajime/cases/73649/build2.zip"
                    def rc = sh(script: cmd, returnStatus: true)
                    println("cmd: $cmd | rc: $rc")
                    if (rc != 0 && rc != 2) {
                        error(cmd)
                    }
                }
            }
        }
    }
}