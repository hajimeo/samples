#!/usr/bin/env python
# -*- coding: utf-8 -*-
# @author Hajime
# $Id: pexpect_runssh.py 15238 2014-02-21 06:15:09Z hajimeosako $
#
'''
Python Expect (Pexpect) wrapper and utility classes

@author: Hajime
'''
try:
    import sys, os, time, getopt, pipes, Queue, logging, smtplib, imp
    from threading import Thread
    from email.MIMEText import MIMEText

    # pxpect.py needs to be in same dir or in PYTHONPATH
    import pexpect
except ImportError, e:
    raise ImportError (str(e))

class RunSsh(object):
    '''
    To run a ssh command against *single* server and return STDOUT as list (array)
    '''
    
    def __init__(self, username=None, hostname='localhost', password=None, passphrase=None, key=None, timeout=30):
        '''
        Constructor
        '''
        self.log = logging.getLogger(hostname)
        if bool(username):
            self.__username = username
        else:
            self.__username = os.getenv("USER")
        self.__hostname = hostname
        self.__password = password
        self.__passphrase = passphrase
        # TODO: not sure if this is a right thing but avoiding empty password/passphrase
        if bool(password) and not bool(passphrase):
            self.__passphrase = password
        if bool(passphrase) and not bool(password):
            self.__password = passphrase
        self.timeout = timeout  # second
        self.ssh_cmd = "ssh -qC -o StrictHostKeyChecking=no"
        self.scp_cmd = "scp -qC -o StrictHostKeyChecking=no"
        if bool(key) and os.path.exists(key):
            self.ssh_cmd = "ssh -qC -o StrictHostKeyChecking=no -i \"%s\"" % str(key)
            self.scp_cmd = "scp -qC -o StrictHostKeyChecking=no -i \"%s\"" % str(key)
        self.terminal_ending = ".+[#\$]\s*$"    # FIXME: supporting '#' and '$' only. adding "%" breaks expect on ubuntu
        self.p = None
        # NOTE: order matters
        self.expecct_replies = []
        self.expect_commons = [self.terminal_ending, pexpect.EOF]
        self.expect_all = self.expecct_replies + self.expect_commons
        #print self.expect_all
    
    def _formatExpectOutput(self):
        '''
        Sometimes pexepct.before is empty (somehow...)
        In that case, use 'after'.
        And also delete the first line (ran command)
         and the last line (command prompt)
        
        @return: modified stdout 
        ''' 
        
        before = self.p.before.rstrip(' \t\n\r')
        after = self.p.after.rstrip(' \t\n\r')
        
        s = before
        if not bool(s): s = after
        
        strs = s.split('\n')
        self.log.debug("strs=%s" % (str(strs)))
        if len(strs) > 1:
            strs_hack = strs[1:(len(strs)-1)]
        else:
            # TODO: if one or two lines, assuming it's a command and/or prompt only
            strs_hack = ""
        strs_hack = "\n".join(strs_hack).rstrip(' \t\n\r')
        self.log.debug("strs_hack=%s" % (str(strs_hack)))
        return strs_hack
    
    def _runExpect(self, ptn):
        i = self.p.expect(ptn)
        self.log.debug("P: %s" % (str(self.p)))
        self.log.debug("Index  : %s %s" % (str(i), ptn[i]))
        self.log.debug("BEFORE : %s" % (self.p.before))
        self.log.debug("AFTER  : %s" % (self.p.after))
        return i
    
    def _runExpectAndResponse(self, cmd, no_spawn=False, no_terminal_ending=False):
        _expect_replies = [".re you sure you want to continue connecting", # 0:needs to update known_hosts
                                ".nter passphrase for key*",                    # 1:passphrase 
                                "s password:",                                    # 2:normal
                                "Password:",                                    # 3:normal
                                ".*password for .*",                            # 4:switch user
                                ]
        
        if not bool(self.expecct_replies):
            self.expecct_replies = _expect_replies
            self.log.debug("Setting default _expect_replies...")
        
        self.expect_all = self.expecct_replies + self.expect_commons
        self.log.debug("expect_all length: %s" % str(len(self.expect_all)))
        
        try:
            if no_spawn == False:
                self.p = pexpect.spawn(command=cmd, timeout=self.timeout, maxread=1048576)
                self.log.debug("Spawned PID %s" % str(self.p.pid))
            else:
                n = self.p.sendline(cmd)
                self.log.debug("1. sendline to PID %s | n = %s" % (str(self.p.pid), str(n)))
            
            #self.log.debug("BUFFER : %s" % (self.p.buffer)) # always empty
            i = self._runExpect(self.expect_all)
            
            if i == 0:
                self.log.info("Asked to store this host as known host.")
                self.p.sendline("yes")
                i = self._runExpect(self.expect_all)
            
            if i == 0:
                self.log.error("Asked to store this host as known host.\nPlease ssh first: %s" % (cmd))
                return False
            elif i == 1:
                self.log.info("Passphrase was requested.")
                if not bool(self.__passphrase):
                    self.log.error("The passphrase is empty for %s." % (self.__hostname))
                    return False
                n = self.p.sendline(self.__passphrase)
                self.log.debug("2. sendline to PID %s | n = %s" % (str(self.p.pid), str(n)))
                i = self._runExpect(self.expect_commons)
                
                if no_terminal_ending == False and i == 1:
                    self.log.error("Could not send passphrase to %s." % (self.__hostname))
                    return False
            elif i == 2 or i == 3 or i == 4:
                self.log.info("(normal) Password was requested.")
                if not bool(self.__password):
                    self.log.error("The password is empty for %s." % (self.__hostname))
                    return False
                n = self.p.sendline(self.__password)
                self.log.debug("3. sendline to PID %s | n = %s" % (str(self.p.pid), str(n)))
                i = self._runExpect(self.expect_commons)
                
                if no_terminal_ending == False and i == 1:
                    self.log.error("Could not send password to %s." % (self.__hostname))
                    return False
            #elif i == 4: # terminal ending means good.
            elif no_terminal_ending == False and i == 6:
                self.log.error("Could not connect to %s." % (self.__hostname))
                return False
            
        except pexpect.TIMEOUT: 
            self.log.error("TIMEOUT on %s." % (self.__hostname))
            self.log.error("If shell prompts does not match %s, TIMEOUT may occur." % (str(self.terminal_ending)))
            return False
        
        return self.p
    
    def sshLogin(self):
        '''
        Handle password and ssh key passphrase
        
        @return: False or pexpect
        '''
        ssh_cmd = "%s %s@%s" % (self.ssh_cmd, self.__username, self.__hostname)
        self.log.info(ssh_cmd)
        return self._runExpectAndResponse(ssh_cmd)
    
    def sshClose(self, force=True):
        self.p.close(force)
    
    def sshInteract(self):
        self.p.interact()
    
    def sshCommand(self, cmd):
        '''
        Run a (normal) command for SSH with Expect
        
        @return: (slightly modified) command output string or false
        '''
        self.log.info("Sending command: %s" % (cmd))
        rtn = ""
        if self._runExpectAndResponse(cmd=cmd, no_spawn=True):
            rtn = self._formatExpectOutput()
        return rtn
    
    def scpScript(self, script_path, random_name=True):
        '''
        Scp script_path (with a random filename)
        
        @return: string filename or False
        '''
        
        if not os.path.exists(script_path):
            self.log.error("%s does not exist." % (str(script_path)))
            return False
        
        base_name = os.path.basename(script_path)
        
        if random_name:
            file_name, file_ext = os.path.splitext(base_name)
            new_name = "%s_%s%s" % (file_name, str(time.time()), file_ext)
        else:
            new_name = base_name
        
        self.log.info("New name is %s" % (new_name))
        
        scp_cmd = "%s %s %s@%s:/tmp/%s" % (self.scp_cmd, script_path, self.__username, self.__hostname, new_name)
        self.log.info("Sending command: %s" % (scp_cmd))
        
        if not self._runExpectAndResponse(cmd=scp_cmd, no_terminal_ending=True):
            self.log.error("%s failed." % (str(scp_cmd)))
            return False
        
        return new_name
    
    def sshScript(self, script_path):
        '''
        Deprecated: Scp script_path with a random filename and run this file
        
        @return: string command to be run or False 
        '''
        
        if not os.path.exists(script_path):
            self.log.error("%s does not exist." % (str(script_path)))
            return False
        
        base_name = os.path.basename(script_path)
        file_name, file_ext = os.path.splitext(base_name)
        new_name = "%s_%s%s" % (file_name, str(time.time()), file_ext)
        self.log.info("New name is %s" % (new_name))
        
        scp_cmd = "%s %s %s@%s:/tmp/%s" % (self.scp_cmd, script_path, self.__username, self.__hostname, new_name)
        self.log.info("Sending command: %s" % (scp_cmd))
        
        if not self._runExpectAndResponse(cmd=scp_cmd, no_terminal_ending=True):
            self.log.error("%s failed." % (str(scp_cmd)))
            return False
        
        cmd = "chmod 755 /tmp/%s 2>/dev/null; /tmp/%s; rm -f /tmp/%s" % (new_name, new_name, new_name)
        self.log.debug(cmd)
        return self.sshCommand(cmd)



class ThreadWorker(Thread):
    '''
    For multi-threading
    Constructor should be Queue, threading Object
    ''' 
    def __init__(self, queue, obj, method_name):
        self.queue = queue
        self.obj = obj
        self.method_name = method_name
        Thread.__init__(self)
    
    def run(self):
        allDone = 0
        while not allDone:    # This is for supporting old python
            try:
                args = self.queue.get(0)
                try:
                    func = getattr(self.obj, self.method_name)
                except AttributeError:
                    # TODO: nicer error handling
                    print "ERROR: %s method does not exist." % (str(self.method_name))
                    raise
                if isinstance(args, dict):
                    func(**args)
                elif isinstance(args, list):
                    func(*args)
                else:
                    func(args)
            except Queue.Empty:
                allDone = 1    # This is for supporting old python



class MyBase(object):
    '''
    Utility class
    
    @requires: logger (for self.log.xxx)
    '''
    log = None

    def __setAttr(self, attr, val):
        #if type(val) == type('str'):
        #    val = pipes.quote(val)
        self.log.debug("Set attr=%s, val=%s" % (attr, val))
        setattr(self, attr, val)
    
    def __getAttr(self, attr, prefix='run'):
        self.log.debug("Get attr=%s" % (attr))
        return getattr(self, prefix+attr)()
    
    def optionsToString(self, options, vertical=False):
        '''
        Convert Options dict to a string to use in help message
        options example: {'u:':'username=', 'p:':'password=', v':'verbose', 'h':'help'}
        '''
        rtn = ""
        
        if vertical:
            for s_opt, l_opt in options.iteritems():
                if s_opt[-1] == ":" and l_opt[-1] == "=":
                    rtn += "    -%s, --%s=STRING" % (s_opt[:(len(s_opt)-1)], l_opt[:(len(l_opt)-1)])
                else:
                    rtn += "    -%s, --%s " % (s_opt, l_opt)
                rtn += os.linesep
        else:
            for s_opt, l_opt in options.iteritems():
                if s_opt[-1] == ":" and l_opt[-1] == "=":
                    rtn += "-%s '%s' " % (s_opt[:(len(s_opt)-1)], l_opt[:(len(l_opt)-1)])
                else:
                    rtn += "-%s (%s) " % (s_opt, l_opt)
            #rtn += os.linesep
        return rtn
    
    def setOptions(self, argv, options={'v' :'verbose', 'h' :'help'}, help_message=None):
        '''
        Handle command arguments and set *this* class properties
        options example: {'u:':'username=', 'p:':'password=', v':'verbose', 'h':'help'}
        '''
        try:
            opts, args = getopt.getopt(argv, ''.join(options.keys()), options.values())
        except getopt.error, msg:
            print msg
            sys.exit(1)
        
        try:
            for opt, val in opts:
                opt = opt.replace('-', '')
                
                if opt in ('h','help'):
                    self.help(help_message)
                elif opt in ('v','verbose'):
                    self.log.setLevel(logging.DEBUG)
                    print "DEBUG: opt=%s" % (str(opts))
                elif opt in options.keys():
                    self.__setAttr(options[opt], True)
                elif opt in options.values():
                    self.__setAttr(opt, True)
                elif opt+":" in options.keys():
                    attr = options[opt+":"].replace('=', '')
                    self.__setAttr(attr, val)
                elif opt+"=" in options.values():
                    self.__setAttr(opt, val)
        except TypeError:
            # TODO: Should it be stopped in here?
            print opts
            raise
    
    def startThreading(self, args_list, obj, method_name, max_threads=5):
        threads = []
        args_queue = Queue.Queue()
        for args in args_list:
            if bool(args): args_queue.put(args)
        
        for i in range(max_threads):
            t = ThreadWorker(args_queue, obj, method_name)
            threads.append(t)
            t.start()
        for t in threads:
            t.join();
        return obj

    def saveTextToFile(self, file_name, text, append=False, rename_if_exist=False):
        '''
        Save text to file
        '''
        # TODO: not sure if this is necessary
        file_name = pipes.quote(file_name)
        
        if rename_if_exist:
            if os.path.isfile(file_name):
                for i in range(1, 10):
                    if not os.path.isfile(file_name+"."+i):
                        file_name = file_name+"."+i
                        break
            if os.path.isfile(file_name):
                self.log.error("Tried to rename but filename %s already exists." % file_name)
                #sys.exit(1)
                return False
        
        try:
            if bool(append):
                self.log.debug("Appending %s (length: %s)..." % (file_name, len(text)))
                f = open(file_name, 'a+b')
            else:
                self.log.debug("Saving %s (length: %s)..." % (file_name, len(text)))
                f = open(file_name, 'wb')
            f.write(text)
            f.close()
            # TODO: is it necessary to modify the file permission...?
            return True
        except:
            self.log.error("Could not save text to %s. text length = %s" % (file_name, len(text)))
            e = sys.exc_info()[1]
            self.log.error(str(e))
            return False
    
    def sendMail(self, sender, recps, subject, body, smtp_ip="127.0.0.1"):
        try:
            if type(recps) == type("string"):
                recps = recps.split(",")
            
            msg = MIMEText(body)
            msg['Subject'] = subject
            msg['From'] = sender
            # TODO: should validate mails.
            msg['To'] = ','.join(recps)
            s = smtplib.SMTP()
            #if self.log.level == logging.DEBUG:
            #    s.set_debuglevel(1)
            #s.connect()
            s.connect(host=smtp_ip)
            self.log.info("Sending an e-mail to %s" % (msg['To']))
            s.sendmail(msg['From'], recps, msg.as_string())
            s.close()
            self.log.info("Probably sent")
            return True
        except:
            self.log.error("Could not send e-mail. text length = %s, To no. = %s..." % (len(body), len(recps)))
            e = sys.exc_info()[1]
            self.log.error(str(e))
            return False
    
    def loadCred(self, conf_file=None):
        # overwriting parameters from credential store file
        if not bool(self.credpath) and bool(conf_file) and os.path.exists(conf_file):
            self.credpath=conf_file
        if bool(self.credpath):
            self.log.info("Using credential store file: %s" % str(self.credpath))
            try:
                confs = imp.load_compiled("*", self.credpath)
                import base64
                if hasattr(confs, 'username'):
                    self.username = base64.b64decode(confs.username)
                if hasattr(confs, 'sudopassword'):
                    self.sudopassword = base64.b64decode(confs.sudopassword)
                if hasattr(confs, 'passphrase'):
                    self.passphrase = base64.b64decode(confs.passphrase)
                if hasattr(confs, 'privatekey'):
                    self.privatekey = base64.b64decode(confs.privatekey)
            except:
                self.log.error("Could not use credential store file:%s" % str(self.credpath))
                raise
        #if not bool(self.sudopassword) and not bool(self.passphrase) and not bool(self.privatekey):
        #    home = os.getenv("HOME")
        #    self.privatekey = "%s/.ssh/id_rsa" % (home)
        #    self.log.info("Using key path: %s" % str(self.privatekey))

    def help(self, help_message=None, is_exiting=True):
        if bool(help_message): print help_message
        else: print self.__doc__
        if is_exiting: sys.exit(0)
    
    def usage(self, help_message=None, is_exiting=True):
        self.help(help_message, is_exiting)
