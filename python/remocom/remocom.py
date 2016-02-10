#!/usr/bin/env python
# -*- coding: utf-8 -*-
# @author Hajime
#
'''
To monitor the following resources:
    date & time
    disk space
    load average

Then send an e-mail to admin
Created on 28/02/2013

Test example:
    ./iremocom.py
    ./remocom.py -u hajime -i 192.168.56.11 -c date
    ./remocom.py -u hajime -i 127.0.0.1,192.168.56.11 -c 'sudo su -;date;whoami'
'''
try:
    import sys, os, time, getopt, getpass, pipes, re, Queue, logging, smtplib, imp
    from threading import Thread
    from email.MIMEText import MIMEText

    # followings need to be in same dir or in PYTHONPATH
    import pexpect
    from pexpect_runssh import *
except ImportError, e:
    raise ImportError (str(e))

class Runner(MyBase):
    '''
    Extend MyBase Class to define business specific logic only
    '''
    def __init__(self):
        self.log = logging.getLogger('runner')
        
        # define class properties (= command arguments)
        self.options = {
                        'a:':'argument=',
                        'c:':'commands=',
                        'f:':'filepath=',
                        'g' :'copyonly',
                        'i:':'hostnames=',
                        'k:':'privatekey=',
                        'm:':'mailto=',
                        'o' :'omit',
                        'p:':'passphrase=',
                        'r' :'raw',
                        's:':'sudopassword=',
                        't:':'title=',
                        'u:':'username=',
                        'v' :'verbose',
                        #'x' :'ibisspecial',
                        'z:':'credpath=',
                        'h' :'help'}
        self.username = None
        self.sudopassword = None
        self.passphrase = None
        self.hostnames = None
        self.commands = None
        self.mailto = None
        self.title = None
        self.filepath = None
        self.argument = None
        self.credpath = None
        self.privatekey = None
        #self.ibisspecial = None
        self.omit = None
        self.raw = None
        self.copyonly = None
        
        self.admin_mail = "admin@hajigle.com"
        self.smtp_ip = "mail.bookmaker.com.au"
        self.timeout = 180
        
        self.max_threads = 5
        self.result = {'str':{}, 'raw':{}, 'rc':{}}
        self.sudo_reg = re.compile(r'(^sudo -s$|^sudo su$|^sudo su -$)')
        self.log_save_dir = None
        self.is_ok = True
    
    def setup(self, argv=None, help_message=None):
        if not bool(argv):
            argv = sys.argv[1:]
        if not bool(argv):
            self.help(help_message)
        
        self.setOptions(argv=argv, options=self.options, help_message=help_message)
        
        default_cred_filename = "."+os.path.basename(os.path.splitext(__file__)[0])+".pyc"
	current_dir_path = os.path.dirname(__file__)+"/"
	default_cred_path = current_dir_path+default_cred_filename
        self.loadCred(default_cred_path)

        if self.sudopassword is None and self.passphrase is None:
            self.sudopassword = getpass.getpass("Sudo pass (optional): ")
        
        if type(self.hostnames) == type("string"):
            self.hostnames = self.hostnames.split(",")
        
        # TODO: can't use ";" in different purpose
        if type(self.commands) == type("string"):
            self.commands = self.commands.split(";")
        
        if bool(self.filepath):
            #if bool(self.commands):
            #    print "Can't use command and file same time."
            #    sys.exit(1)
            if not os.path.exists(self.filepath):
                print "File %s does not exist." % (self.filepath)
                sys.exit(1)
    
    def report(self):
        if bool(self.raw):
            print self.result['raw']
        
        if bool(self.mailto):
            if bool(self.title):
                mail_title = self.title
            elif not self.is_ok:
                mail_title = "Server monitoring *** ALERT ***"
            else:
                mail_title = "Server monitoring"
            
            #FIXME: at this moment, send e-mail only if it's not empty
            is_sending_email = False
            for host, obj in self.result['raw'].iteritems():
                # If any error, sends e-mail.
                if self.result['rc'][host] > 0:
                    is_sending_email = True
                    break
                
                for cmd, out in obj.iteritems():
                    if len(out) > 0:
                        is_sending_email = True
                        break
            
            # If something special, doesn't care rc/raw results
            #if self.ibisspecial:
            #    is_sending_email = True
            
            if not is_sending_email:
                print "NOT sending \"%s\" to %s via %s" % (mail_title, self.mailto, self.smtp_ip)
                return
                
            mail_body = ""
            for host, lines in self.result['str'].iteritems():
                if lines:
                    mail_body += lines+"\n"
            #print mail_body
        
            # sending an e-mail even if it's empty
            # TODO: no mail validation.
            print "Sending \"%s\" to %s via %s" % (mail_title, self.mailto, self.smtp_ip)
            mail_result = self.sendMail(self.admin_mail, self.mailto, mail_title, mail_body, self.smtp_ip)
    
    def runInner(self, host):
        '''
        Decides each host's output and logging
        '''
        rs = RunSsh(self.username, host, self.sudopassword, self.passphrase, self.privatekey, self.timeout)
        if bool(self.log.level): rs.log.setLevel(self.log.level)
        
        # resetting result for this host
        self.result['rc'][host] = 0
        self.result['str'][host] = ""
        self.result['raw'][host] = {}
        
        result_header = "### %s \"%s\" ######\n\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), host)
        result_str = ""
        file_name = ""
        
        # SCP first
        if bool(self.filepath):
            self.log.info("command file path = %s" % (self.filepath))
            random_name = True
            if self.copyonly:
                random_name = False
            file_name = rs.scpScript(self.filepath, random_name)
            self.log.debug(file_name)
        
        if bool(self.commands) or bool(self.filepath): # or self.ibisspecial:
            if (not rs.sshLogin()):
                # Decided to ignore connection error
                self.result['rc'][host] = -1
                result_str += "--- Login/Connection error ---\n\n"
            else:
                # in case of sudo, run commands before script file
                if bool(self.commands):
                    i=1
                    for cmd in self.commands:
                        cmd = cmd.strip()
                        if len(cmd) > 0 :
                            # trying not to save in script history
                            ssh_result = rs.sshCommand(' '+cmd)
                            ssh_result = str(ssh_result).strip()
                            self.log.debug("return %s" % ssh_result)
                            
                            if not self.sudo_reg.search(cmd):
                                # If omit is set and no result, don't include in result
                                if not self.omit or ssh_result:
                                    result_str += "[%s] %s\n%s\n\n" % (i, cmd, ssh_result)
                                
                                self.result['raw'][host][cmd] = ssh_result
                                i+=1
                
                if bool(self.filepath) and not self.copyonly:
                    if file_name == "":
                        self.result['rc'][host] = 1
                        result_str += "--- Script file sending error ---\n\n"
                    else:
                        self.log.info("command file path = %s" % (self.filepath))
                        base_name = os.path.basename(self.filepath)
                        # it seems FreeBSD does not like "2>/dev/null". Maybe because default shell is csh.
                        # FIXME: Assuming the terget server has 'sh'
                        cmd = "sh -c 'chmod 755 /tmp/%s;/tmp/%s %s;rm -f /tmp/%s'" % (file_name, file_name, self.argument, file_name)
                        ssh_result = rs.sshCommand(cmd)
                        ssh_result = str(ssh_result).strip()
                        # If omit is set and no result, don't include in result
                        if not self.omit or ssh_result:
                            result_str += "[%s] %s\n%s\n\n" % (str(1), base_name, ssh_result)
                        
                        self.result['raw'][host][base_name] = ssh_result
                
                #### Run IBIS server monitoring report ############################
                #if self.ibisspecial:
                #    result_str += self._specialChecks(rs)
        
        # sometimes can't close ssh, so that check 'p' first.
        if rs.p is None:
            self.log.error("p for %s is empty." % (host))
            self.is_ok = False
        else:
            rs.sshClose()
        
        if not self.omit or result_str:
            self.result['str'][host] = "%s%s" % (result_header, result_str)
        
        if not bool(self.raw):
            if not self.omit or result_str:
                print "%s%s\n" % (result_header, result_str)
        
        # saving string into a file "hostname_%w.log"
        if bool(self.log_save_dir) and os.path.isdir(self.log_save_dir):
            N = time.strftime("%w")
            file_name = self.log_save_dir + os.sep + host + "_" + str(N) + ".log"
            self.log.info("saving outputs into a file %s ." % (file_name))
            # decide appending or truncating
            # if newer than 7 days ago, appending
            if os.path.isfile(file_name) and (os.path.getctime(file_name) > (time.time() - 60*60*24*7)):
                self.saveTextToFile(file_name, result_str, True)
            else:
                self.saveTextToFile(file_name, result_str, False)
    
    def _specialChecks(self, rs):
        '''
        Define servers' alerts/checks in here
        '''
        rtn_str = ""
        rs.sshCommand("sudo su -")
        _is_ok = True
        
        # 1. Checking time difference
        current_unix_timestamp = time.time()
        remote_unix_timestamp = rs.sshCommand('date +"%s"')
        try:
            if abs(int(remote_unix_timestamp) - current_unix_timestamp) >= 60:
                rtn_str += "*ALERT* : Check server date (diff: %d)\n\n" % (abs(remote_unix_timestamp - current_unix_timestamp))
                _is_ok = False
        except:
                rtn_str += "*WARN* : Could not check date on this server (%s)\n\n" % (str(remote_unix_timestamp))
                _is_ok = False
        
        # 2. Disk space
        df_str = rs.sshCommand("df -lh | grep ^/ | grep -vE '(/media/|/mnt/|/backups)' | egrep '(100%|9[0-9]%)'")
        if bool(df_str):
            rtn_str += "*ALERT* : Check disk space (%s)\n\n" % (df_str)
            _is_ok = False
        
        # 3. CPU usage
        la_str = rs.sshCommand("uptime | cut -d ',' -f 5")
        try:
            if float(la_str) > 2:
                rtn_str += "*ALERT* : Check CPU (Load Avg. %s)\n\n" % (la_str)
                _is_ok = False
        except:
                rtn_str += "*WARN* : Please review Check \"uptime | cut -d ',' -f 5\" (%s)\n\n" % (la_str)
                _is_ok = False
        
        # 3. Modified etc file
        #find_str = rs.sshCommand("find /etc/ -type f -mmin -181 -ls | grep -v \.svn")
        #if bool(find_str):
        #    rtn_str += "*ALERT* : Check etc file(s)%s%s%s%s" % (os.linesep, find_str, os.linesep, os.linesep)
        #    self.is_ok = False
        
        if not _is_ok:
            self.is_ok = _is_ok
            for i, cmd in enumerate(["w | grep -vw w", "df -lh | grep -E '(^/|^Filesystem)'", "vmstat 2 2", "top -bd1 | head -n13", "netstat -an | grep -wE '(80|443|5432)'", "grep -o -E ' PHP (Fatal|Parse).*$' /var/log/php-error.log | sort | uniq -c | sort -nr | head -n5"]):
                time.sleep(1)
                rtn_str += "[%s] %s\n%s\n\n" % ((i+1), cmd, rs.sshCommand(cmd))
        else:
            for i, cmd in enumerate(["w | grep -vw w", "df -lh | grep -E '(^/|^Filesystem)'"]):
                time.sleep(1)
                rtn_str += "[%s] %s\n%s\n\n" % ((i+1), cmd, rs.sshCommand(cmd))
        
        return rtn_str



if __name__ == '__main__':
    logging.basicConfig()
    #file_name=os.path.basename(__file__)
    default_hostnames = ""
    
    r = Runner()
    r.setup(help_message='''Run one or multiple commands to monitor multiple servers.
TODO:
    At this moment, complex command (pipe "|", redirection "<>", substitution "()") fails.

Usage:
    ./remocom.py %s

Example:
    ./remocom.py
    ./remocom.py -u 'hajime' -i '192.168.56.11' -c 'date'
    ./remocom.py -u 'hajime' -i '127.0.0.1,192.168.56.11' -c 'sudo su -;date;whoami'
    ./remocom.py -i '127.0.0.1,192.168.56.11' -c 'sudo su -;date;whoami' -m hajime.osako@harmonyseasia.com -t 'Mail sending test'
    ./remocom.py -i '127.0.0.1,192.168.56.11' -f test.sh -c 'sudo -s'

IP/Hosts (used with -i)
    Default: %s
''' % (r.optionsToString(r.options), default_hostnames))
    
    r.log_save_dir = "/var/log/remocom"
    if not bool(r.hostnames):
        r.hostnames = default_hostnames.split(",")
    
    r.startThreading(args_list=r.hostnames, obj=r, method_name="runInner")
    r.report()
