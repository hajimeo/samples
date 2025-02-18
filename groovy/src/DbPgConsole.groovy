/*
sysPath="/opt/sonatype/nexus/system"
#groovyJar="${sysPath%/}/org/codehaus/groovy/groovy-all/2.4.17/groovy-all-2.4.17.jar"
groovyJar="${sysPath%/}/org/codehaus/groovy/groovy/3.0.19/groovy-3.0.19.jar"
java -Dgroovy.classpath="${sysPath%/}/org/codehaus/groovy/groovy-sql/3.0.19/groovy-sql-3.0.19.jar:$(find ${sysPath%/}/org/postgresql/postgresql -type f -name 'postgresql-*.jar' | tail -n1):$(find ${sysPath%/}/com/h2database/h2 -type f -name 'h2-*.jar' | tail -n1)" -jar  "${groovyJar}" \
    $HOME/IdeaProjects/samples/groovy/src/DbPgConsole.groovy
 */
org.h2.tools.Server.createWebServer("-webPort", "18082", "-webAllowOthers", "-ifExists").start()