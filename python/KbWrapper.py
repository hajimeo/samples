#!/usr/bin/env python
# -*- coding: utf-8 -*-
'''
SalesForce Search & Download KB articles
Created on 25/04/2011

@author: Hajime

NOTE: Please change self.kbwHome
@todo: currently doesn'w work with PDF, Word etc.

curl -L 'https://na63.salesforce.com/knowledge/knowledgeHome.apexp' -H 'Accept-Encoding: gzip, deflate, sdch' -H 'Accept-Language: en-AU,en;q=0.8' -H 'Upgrade-Insecure-Requests: 1' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.101 Safari/537.36' -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' -H 'Connection: keep-alive' --compressed

curl -L 'https://na63.salesforce.com/knowledge/knowledgeHome.apexp' --data '
    AJAXREQUEST=_viewRoot&
    j_id0%3AknowledgeForm=j_id0%3AknowledgeForm&
    searchInput=&
    spellOff=false&
    articleType_Best_Practices__kav=on&
    articleType_How_To_Questions__kav=on&
    articleType_Technical_Issues__kav=on&
    categoryType_0D1G0000000TNLV=02nG0000000TUw6&
    categoryType_0D1G0000000TNLG=02nG0000000TUvN&
    categoryType_0D1G0000000TNLL=02nG0000000TUvm&
    com.salesforce.visualforce.ViewState=i%3AA...%3D%3D&
    com.salesforce.visualforce.ViewStateVersion=201808092020470234&
    com.salesforce.visualforce.ViewStateMAC=AG...fS3N0WT0%3D&
    com.salesforce.visualforce.ViewStateCSRF=Vmp...FJp&
    j_id0%3AknowledgeForm%3Aj_id50=j_id0%3AknowledgeForm%3Aj_id50&
' --compressed
'''

import sys, os, urllib, urllib2, cookielib, time, re, getopt, pickle, pipes, subprocess
import smtplib
from email.MIMEText import MIMEText
import logging

logging.basicConfig()


class KbWrapper(object):
    '''
    Search & Download KB articles
    '''

    def __init__(self, username=None, password=None, workPath='./'):
        '''
        Constructor
        '''
        self.log = logging.getLogger("KbW")
        self.__username = username
        self.__password = password
        self.__workPath = pipes.quote(workPath)
        self.__ckPath = self.__workPath + "cookie." + str(self.__username) + ".txt"
        self.timeout = 25 * 60  # second
        self.sizeMin = 36000  # 40714 (win) -> 39301 (lin). Smallest KM article so far is 41K
        self.ssoHome = "https://na63.salesforce.com"
        self.ckJar = cookielib.MozillaCookieJar(self.__ckPath)
        # make sure the file exists
        if os.path.isfile(self.__ckPath) and os.path.getmtime(self.__ckPath) > (time.time() - self.timeout) and int(
                os.path.getsize(self.__ckPath)) > 512:
            self.ckJar.load(ignore_discard=True)
        else:
            open(self.__ckPath, 'a').close()
            self.__chmod(self.__ckPath)

        self.opener = urllib2.build_opener(urllib2.HTTPCookieProcessor(self.ckJar))
        self.prevUrl = None
        self.baseParams = {'advanced': 'true',
                           'query.queryType': 'ADVANCED',
                           'query.filteredProducts': 'true',
                           '_query.filteredProducts': 'on',
                           'audience': 'SS',
                           'hasSupportedContracts': 'true',
                           '_relatedSubProductSearch': 'on',
                           '_query.products': '1',
                           'query.version': '-',
                           'query.operatingSystem': '-',
                           '_query.documentCategories': 'on',
                           # 'query.documentCategories':'technical_documents',
                           'search-action': 'Search »'}
        self.adminMail = "atscale@hajigle.com"
        self.result = None
        self.lastList = None
        self.preCache = True

        self.baseReg = re.compile(r'<base [^>]*?>', re.IGNORECASE)
        self.headReg = re.compile(r'<head[^>]*?>', re.IGNORECASE)
        self.kmidReg = re.compile(r'KM\d+', re.IGNORECASE)
        self.tagsReg = re.compile(r'<[^>]*?>')

    def __sendMail(self, sender, recps, subject, body):
        try:
            if self.log.level == logging.DEBUG:
                self.log.debug("Debug mode sends to sender= %s..." % (sender))
                recps = [sender]
            if type(recps) == type("a"):
                recps = [recps]

            msg = MIMEText(body)
            msg['Subject'] = subject
            msg['From'] = sender
            # TODO: should validate mails.
            msg['To'] = ','.join(recps)
            s = smtplib.SMTP()
            if self.log.level == logging.DEBUG:
                s.set_debuglevel(1)
            s.connect(host=self.smtp_host)
            self.log.debug("Sending e-mail. text length = %s, To no. = %s..." % (len(body), len(recps)))
            s.sendmail(msg['From'], recps, msg.as_string())
            s.close()
        except:
            self.log.error("Could not send e-mail. text length = %s, To no. = %s..." % (len(body), len(recps)))
            e = sys.exc_info()[1]
            self.log.error(str(e))

    def __chmod(self, path, perm=0666):
        try:
            os.chmod(path, perm)
        except:
            self.log.debug('Could not change permission %s to %s' % (path, str(perm)))

    def search(self, word=None, params={'query.products': 'SRVA', 'query.documentCategories': 'technical_documents',
                                        'query.sortField': 'SORT_FIELD_MOSTVIEWED'}):
        '''
        search KM or Manual
        Return HTML
        '''
        if bool(word):
            self.log.debug('Search word = "%s"' % (word))

            # TODO: may not right place to implement
            # SSO returns totally different result by allwords and exactphrase
            # so if word starts with " and end with ", use exactphrase
            r = re.search('^"(.+)"$', word)
            if bool(r):
                word = r.group(1)  # deleting " which would not work with exactphrase
                params['query.exactPhrase'] = word
            else:
                params['query.allWords'] = word
            # if bool(r):
            #    params['query.searchType'] = "exactphrase"
            #    word = r.group(1)   # deleting " which would not work with exactphrase
            # else:
            #    params['query.searchType'] = "allwords"

            # words = {'query.searchString':word}
            # params = dict(self.baseParams.items() + params.items() + words.items())

        params = dict(self.baseParams.items() + params.items())

        paramStr = urllib.urlencode(params)
        self.result = self.urlOpen(self.ssoHome + "/selfsolve/documents", paramStr)
        return self.result

    def runSearch(self, word, category=None, doctype=None, text=True):
        '''
        Search Technical documents (KCS article) only
        Return text in default (text=True)
        '''
        if not bool(category): category = "SRVA"
        if not bool(doctype):  doctype = "technical_documents"

        html = self.search(word, {'query.products': category, 'query.documentCategories': doctype,
                                  'query.sortField': 'SORT_FIELD_MOSTVIEWED'})

        if text:
            result = self.getKMText(html)
        else:
            result = html

        self.saveHtml("search." + str(self.__username) + ".htm", result)

        # TODO: should run below steps in background
        if doctype == "technical_documents" and self.preCache:
            ids = []
            for line in self.lastList:
                if bool(line[0]):
                    ids += [line[0]]

            if len(ids) > 0 and len(ids) < 6:
                idsText = ','.join(ids)
                # TODO: this part isn't good.
                # pid = os.system("nohup ./KbWrapper.py -t %s -u %s -p %s -i %s &" % (self.__workPath, self.__username, self.__password, idsText))
                cmd = "nohup ./KbWrapper.py -t %s -u %s -p %s -i %s &" % (
                self.__workPath, self.__username, self.__password, idsText)
                self.log.debug("Creating bg process with %s" % (str(cmd)))
                p = subprocess.Popen(cmd, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE)
                self.log.debug("background process %s was created." % (str(p.pid)))

        return result

    def getKM(self, id, reuse=False):
        '''
        Download one KM articles
        Reuse = False would be fine because PHP side is controlling
        Return HTML if id is only one, otherwise saved IDs
        '''
        id = str.upper(id)
        ids = id.split(',')
        html = None
        savedIDs = []

        for id2 in ids:
            html = None

            if self.kmidReg.match(id2) is None:
                print "ERROR: ID %s doesn't look like KM ID." % (str(id2))
                continue

            # If ID is only one, always get new data
            if len(ids) != 1 and reuse:
                html = self.loadText(id2 + ".htm")

            # TODO: (low) check smallest KM article.
            if not bool(html) or (len(html) < self.sizeMin):
                html = self.urlOpen(self.ssoHome + "/selfsolve/document/" + id2)

                if bool(html):
                    self.saveHtml(id2 + ".htm", html)
                    savedIDs.append(id2)

        if len(ids) == 1:
            return html
        else:
            return savedIDs

    def downloadKMs(self, word=None, category=None, doctype=None, all=False):
        '''
        Search KCS and saves KM articles. if all=True, download if does not exist.
        Note: the filed sort order is SORT_FIELD_DATE
        Returns list of saved KCS ID
        '''
        if not bool(category): category = "SRVA"
        if not bool(doctype):  doctype = "technical_documents"

        savedIDs = []
        html = self.search(word=word, params={'query.products': category, 'query.documentCategories': doctype,
                                              'query.sortField': 'SORT_FIELD_DATE'})
        self.saveHtml("downloadKMs." + str(self.__username) + ".htm", html)

        if all:
            savedIDs += self.saveKMsInPage(html=html, newOnly=True)
            hrefs = self.getNextPageList(html)
            self.log.debug("Find %s next pages." % (len(hrefs)))

            for href in hrefs:
                tmpHtml = self.urlOpen(href)
                savedIDs += self.saveKMsInPage(tmpHtml)
        else:
            savedIDs += self.saveKMsInPage(html=html, newOnly=False)

        return savedIDs

    def downloadNewKMs(self, category=None, doctype=None):
        '''
        Comparing KM IDs which are saved in a list and returning KMs not in a list
        Sort order is SORT_FIELD_DATE. Getting only one page (22 items?)
        Returns list of saved KCS ID
        Also sends e-mail.
        '''
        if not bool(category): category = "SRVA"
        if not bool(doctype):  doctype = "technical_documents"

        # load saved KM IDs. If doesn't exist, treat all KMs as new
        fileName = "prevKMs_" + str(category) + "_" + str(doctype) + ".dmp"

        if self.isExist(fileName):
            prevIDs = self.loadPickle(fileName)
        else:
            self.log.debug("File %s does not exist." % (fileName))
            prevIDs = []

        # get probably new KM IDs
        html = self.search(word=None, params={'query.products': category, 'query.documentCategories': doctype,
                                              'query.sortField': 'SORT_FIELD_DATE'})
        self.saveHtml("downloadNewKMs." + str(self.__username) + ".htm", html)
        list = self.getKMList(html=html, idAsKey=True)

        # TODO: testing below. sometimes even cookie looks ok, it fails, so adding login.
        if len(list) == 0:
            self.login()
            self.opener.open(self.ssoHome + "/selfsolve/documents")
            html = self.search(word=None, params={'query.products': category, 'query.documentCategories': doctype,
                                                  'query.sortField': 'SORT_FIELD_DATE'})
            self.saveHtml("downloadNewKMs." + str(self.__username) + ".htm", html)
            list = self.getKMList(html=html, idAsKey=True)

        # save KM IDs
        savedIDs = []
        currentIDs = list.keys()

        for id in currentIDs:
            htmFileName = id + ".htm"
            if id in prevIDs and self.isExist(htmFileName):
                self.log.debug("ID %s is already in the list (%s) and exists." % (id, len(prevIDs)))
                continue

            tmpHtml = self.urlOpen(self.ssoHome + "/selfsolve/document/" + id)
            self.saveHtml(htmFileName, tmpHtml)
            savedIDs.append(id)

        self.savePickle(fileName, currentIDs)

        # if len(currentIDs) > 30:
        #    print "ERROR: Looks like too many current IDs %s" % (len(currentIDs))
        #    return savedIDs
        #
        # for id in currentIDs:
        #    htmFileName = id+".htm"
        #    tmpHtml = self.urlOpen(self.ssoHome+"/selfsolve/document/"+id)
        #    
        #    result = self.saveHtml(fileName=htmFileName, html=tmpHtml, forceWrite=False)
        #    if result:
        #        savedIDs.append(id)
        #
        ## TODO: No longer using prevKMs_xxxx but saving
        # self.savePickle(fileName, currentIDs)

        if len(savedIDs) > 0:
            self.log.debug("Trying to send e-mail | savedIDs len: %s" % (len(savedIDs)))
            mlFileName = "mailList_" + str(category) + "_" + str(doctype) + ".dmp"
            mails = self.loadPickle(mlFileName)
            # Send e-mail if prevIDs is not empty
            if bool(mails) and len(prevIDs) > 0:
                self.log.debug("start sending e-mails | prevIDs len: %s" % (len(prevIDs)))
                text = ""

                for id in savedIDs:
                    # TODO: this link (hard-coding 'tmp') is not good.
                    text += '%s/?i=%s\n%s\n\n' % (self.kbwHome, id, list[id])

                self.__sendMail(self.adminMail, mails, "New KCS articles for %s : %s" % (category, doctype), text)

        return savedIDs

    def saveKMsInPage(self, html, newOnly=False):
        list = self.getKMList(html=html, idAsKey=True)
        savedIDs = []

        for id in list.keys():
            fileName = id + ".htm"

            if newOnly and self.isExist(fileName):
                self.log.debug("File %s already downloaded." % (fileName))
                continue

            tmpHtml = self.urlOpen(self.ssoHome + "/selfsolve/document/" + id)
            self.saveHtml(fileName, tmpHtml)
            savedIDs.append(id)

        return savedIDs

    def pingSSO(self, autoLogin=True):
        '''
        Just refreshing page.
        Return string (HTML) length.
        '''
        self.result = self.urlOpen(self.ssoHome + "/selfsolve/documents")
        self.saveHtml("ping." + str(self.__username) + ".htm", self.result)

        if autoLogin and len(self.result) < self.sizeMin:
            self.log.debug("The result length %s is smaller than sizeMin %s." % (len(self.result), self.sizeMin))
            self.login()
        return len(self.result)

    def getKMText(self, html=None):
        '''
        Create a simple text output from List
        Return text
        '''
        self.lastList = self.getKMList(html)
        result = ""

        for line in self.lastList:
            result += line[0] + "\t" + line[1] + "\n"

        return result

    def getKMList(self, html=None, idAsKey=False):
        '''
        search 'a href' contains KMXXXXXX
        Return a dictionary : KM, Label(text), Date
        '''
        if not html:
            html = self.result

        import BeautifulSoup
        bs = BeautifulSoup.BeautifulSoup(html)
        # TODO: Would like to get the Link and Date properly...
        links = bs.findAll('a', href=self.kmidReg)

        if idAsKey:
            list = {}
        else:
            list = []

        for link in links:
            text = str.strip(self.tagsReg.sub('', str(link)))
            if len(text) < 5:
                continue
            try:
                id = self.kmidReg.search(str(link)).group()
            except:
                print "Failed Link= %s" % link
                # raise

            if idAsKey:
                list[id] = text
            else:
                list.append([id, text])

        return list

    def getNextPageList(self, html=None):
        '''
        search 'a href' contains KMXXXXXX
        Return a list of href 
        '''
        if not bool(html):
            html = self.result

        import BeautifulSoup
        bs = BeautifulSoup.BeautifulSoup(html)
        links = bs.findAll('a', href=re.compile(r'documents\?results=true&page=\d+'))

        list = []
        for link in links:
            text = str.strip(self.tagsReg.sub('', str(link)))
            # eliminating 'Next' and 'Last'
            if not text.isdigit():
                continue
            list.append(link['href'])

        return list

    def addBase(self, html):
        # find <base>
        base = '<base href="%s/selfsolve/document/">' % (self.ssoHome)

        if self.baseReg.search(str(html)) is None:
            self.log.debug("Adding base after <head>...")
            # TODO: lazy to think proper regex.
            html = self.headReg.sub("<head>" + base, str(html))
        else:
            self.log.debug("Replacing base...")
            html = self.baseReg.sub(base, str(html))
        return html

    def addMail(self, mail, category=None, doctype=None, unsub=True):
        '''
        Save given mail address in pickle
        If unsub is true and e-mail is already registered, delete.
        Return a number of mail list
        '''
        if re.match(r"^[a-zA-Z0-9._%-]+@hp\.com$", mail) is None:
            print "ERROR: E-mail %s doesn't look like HP e-mail address." % (str(mail))
            return

        if not bool(category): category = "SRVA"
        if not bool(doctype):  doctype = "technical_documents"
        fileName = "mailList_" + str(category) + "_" + str(doctype) + ".dmp"

        if self.isExist(fileName):
            mails = self.loadPickle(fileName)
        else:
            self.log.debug("File %s does not exist." % (fileName))
            mails = []

        if not mail in mails:
            self.log.debug("Mail %s does not exist yet. Adding..." % (mail))
            mails.append(mail)
            self.savePickle(fileName, mails)

            text = "Added %s for %s : %s" % (mail, category, doctype)
            self.__sendMail(self.adminMail, mail, "New subscription for %s : %s" % (category, doctype), text)
            # TODO: sending e-mail to me to make sure downloadNewKMs works for selected category...
            self.__sendMail(self.adminMail, self.adminMail, "New subscription for %s : %s" % (category, doctype), text)
            print text
        else:
            self.log.debug("Mail %s exists." % (mail))
            if unsub:
                self.log.debug("Removing...")
                mails.remove(mail)
                self.savePickle(fileName, mails)
                text = "Unsbscribed %s from %s : %s\r\n\r\n" % (mail, category, doctype)
                text += "If you would like to subscribe again, click %s/?mail=%s" % (self.kbwHome, mail)
                self.__sendMail(self.adminMail, mail, "Unsubscription for %s : %s" % (category, doctype), text)
                print "Mail %s was unsubscribed." % (mail)
            else:
                print "Mail %s was already registered." % (mail)
        return len(mails)

    def isExist(self, fileName, quote=True):
        if quote:
            fileName = pipes.quote(fileName)
        return os.path.isfile(self.__workPath + fileName)

    def loadText(self, fileName):
        text = None
        if self.isExist(fileName):
            f = open(self.__workPath + fileName, 'r')
            text = f.read()
            f.close()
        return text

    def saveHtml(self, fileName, html, renameIfExists=False, forceWrite=True):
        '''
        Save html to file
        '''
        fileName = pipes.quote(fileName)
        self.log.debug("Adding Base tag...")
        html = self.addBase(html)

        if renameIfExists:
            if self.isExist(fileName, False):
                for i in range(1, 10):
                    if not self.isExist(fileName + "." + i):
                        fileName = fileName + "." + i
                        break
            if self.isExist(fileName, False):
                print "Tried rename but filename %s already exists."
                sys.exit(1)
                return False

        if not forceWrite and self.isExist(fileName, False):
            oldHtml = self.loadText(fileName)
            if oldHtml == html:
                self.log.debug("Same file for %s already exists" % (fileName))
                return False

        self.log.debug("Saving %s (%s)..." % (fileName, len(html)))
        f = open(self.__workPath + fileName, 'wb')
        f.write(html)
        f.close()
        # TODO: is this necessary to modify the file permission...
        self.__chmod(self.__workPath + fileName)
        return True

    def savePickle(self, fileName, object):
        '''
        Save object to file
        '''
        fileName = pipes.quote(fileName)
        self.log.debug("Saving pickle %s..." % (fileName))
        fp = open(self.__workPath + fileName, 'w')
        pickle.dump(object, fp)
        fp.close()

        # TODO: is this necessary to modify the file permission...
        self.__chmod(self.__workPath + fileName)
        return

    def loadPickle(self, fileName):
        '''
        Return object from file
        '''
        fileName = pipes.quote(fileName)
        object = None

        if self.isExist(fileName, False):
            self.log.debug("Loading pickle %s." % (fileName))
            fp = open(self.__workPath + fileName, 'r')
            object = pickle.load(fp)
            fp.close()

        return object

    def login(self):
        '''
        login to SSO
        '''
        url = 'https://ovrd.external.hp.com/rd/sign-in'
        self.log.debug("Logging in to %s..." % url)
        self.opener.open(url)

        if not bool(self.__username):
            print "Credential is required."
            sys.exit(1)

        params = {'signInName': self.__username,
                  'password': self.__password,
                  'sign-in': 'Sign-in »',
                  'target': None,
                  }
        paramStr = urllib.urlencode(params)
        try:
            self.log.debug("Posting to %s with '%s' ..." % (url, paramStr))
            self.opener.open(url, paramStr)
        except urllib2.HTTPError, e:
            if str(e.code) != '404':
                raise
            else:
                self.log.debug("Received 404 (expected).")

    def urlOpen(self, url, data=None, retry=True):
        '''
        open url and if redirected (this is not good enough), re-login.
        Return strings (HTML)
        '''
        if url.find(self.ssoHome) == -1:
            self.log.debug("Url %s does not start with %s." % (url, self.ssoHome))
            url = self.ssoHome + url

        # If session has NOT been expired.
        if os.path.getsize(self.__ckPath) > 0 and os.path.getmtime(self.__ckPath) > (time.time() - self.timeout):
            self.log.debug("Cookie file is newer than timeout %s." % (self.timeout))
            cookieSize = int(os.path.getsize(self.__ckPath))
            if cookieSize > 1800:
                self.log.debug("Cookie file is bigger than 1800 (%s)." % (cookieSize))
                pass
            # Probably SSO is checking referrer, so opening a url before posting.
            elif self.prevUrl is None or self.prevUrl != url:
                self.log.debug("URL %s is different from Previous URL %s." % (url, self.prevUrl))
                self.log.debug("Opening %s' ..." % (url))
                self.opener.open(url)
        else:
            self.log.debug("Cookie file is older than timeout %s." % (self.timeout))
            self.login()
            self.log.debug("Opening %s' ..." % (url))
            self.opener.open(url)

        self.log.debug("Opening %s with '%s' ..." % (url, data))
        f = self.opener.open(url, data)
        result = f.read()

        # TODO: could not detect if SSO redirects by checking f.url
        self.log.debug("result length= %s. sizeMin= %s " % (len(result), self.sizeMin))
        if retry and len(result) < self.sizeMin:
            self.log.debug("Re-logging in and Retrying %s with %s ..." % (url, data))
            self.login()
            result = self.urlOpen(url=url, data=data, retry=False)

        self.prevUrl = url
        self.ckJar.save(filename=self.__ckPath, ignore_discard=True)
        return result

    def runner(self, args):
        '''
        Run methods by arguments
        id > mail > downloadNew > download > downloadAll > word
        Return text
        '''
        if bool(args['kbwhost']):
            self.kbwHome = "http://%s/kbwrapper" % (str(args['kbwhost']))
            self.log.debug("kbwHome changed to %s " % (self.kbwHome))

        if bool(args['id']):
            result = self.getKM(args['id'])
            if result and self.log.level == logging.DEBUG:
                import AddIndex
                self.log.debug("Adding Index for %s id." % (args['id']))
                AI = AddIndex.AddIndex(workPath=args['tempdir'])
                AI.addIndex(args['id'])
            return result

        if bool(args['mail']):
            return self.addMail(mail=args['mail'], category=args['category'], doctype=args['doctype'])

        if bool(args['downloadNew']):
            list = self.downloadNewKMs(category=args['category'], doctype=args['doctype'])

            if len(list) > 0:
                try:
                    import AddIndex
                    self.log.debug("Adding Index for %s ids." % (len(list)))
                    AI = AddIndex.AddIndex(workPath=args['tempdir'])

                    for id in list:
                        try:
                            aiResult = AI.addIndex(id)
                            if bool(aiResult):
                                self.log.debug("Probably added %s." % (id))
                            else:
                                sys.stderr.write("ERROR: Probably failed to add %s." % (id))
                        except:
                            self.log.exception("ERROR: Failed to add %s." % (id))
                except:
                    self.log.debug("No AddIndex class. Skipping.")

            return str(list)

        if bool(args['download']):
            list = self.downloadKMs(word=args['word'], category=args['category'], doctype=args['doctype'], all=False)
            return str(list)

        if bool(args['downloadAll']):
            list = self.downloadKMs(word=args['word'], category=args['category'], doctype=args['doctype'], all=True)
            return str(list)

        if bool(args['word']):
            return self.runSearch(word=args['word'], category=args['category'], doctype=args['doctype'], text=True)

        return None


# TODO: Not sure if this is an efficient way.
from SocketServer import *


class KbWrapServer(BaseRequestHandler):
    def handle(self):
        global KBW
        KBW.log.debug("connected from: %s" % (str(self.client_address)))

        while True:
            msg = self.request.recv(8192)
            if len(msg) == 0:
                KBW.log.debug("no msg. break.")
                break
            hArgs = getOptions(msg.split())
            KBW.log.debug("Options= %s." % (hArgs))

            text = KBW.runner(hArgs)

            if text is None:
                KBW.log.debug("Nothing to do by msg %s." % (str(msg)))
                continue

            KBW.log.debug("text length = %s." % (len(text)))
            self.request.send(text)
        self.request.close()


def getOptions(argv):
    rtnargs = {}
    # Set default values:
    rtnargs['username'] = None
    rtnargs['password'] = None
    rtnargs['word'] = None
    rtnargs['category'] = None
    rtnargs['doctype'] = None
    rtnargs['mail'] = None
    rtnargs['id'] = None
    rtnargs['kbwhost'] = None
    rtnargs['tempdir'] = "/tmp/"
    rtnargs['debug'] = False
    rtnargs['service'] = False
    rtnargs['help'] = False
    rtnargs['download'] = False
    rtnargs['downloadNew'] = False
    rtnargs['downloadAll'] = False

    try:
        opts, args = getopt.getopt(argv, 'u:p:w:c:d:t:i:k:h',
                                   ['username=', 'password=', 'word=', 'category=', 'doctype=', 'tempdir=', 'id=',
                                    'mail=', 'kbwhost='
                                       , 'downloadAll', 'downloadNew', 'download', 'service', 'debug', 'help'])
    except getopt.error, msg:
        print msg
        sys.exit(1)

    try:
        for opt, val in opts:
            if opt in ('-h', '--help'):
                rtnargs['help'] = True
            elif opt in ('-u', '--username'):
                rtnargs['username'] = val
            elif opt in ('-p', '--password'):
                rtnargs['password'] = val
            elif opt in ('-w', '--word'):
                rtnargs['word'] = val
            elif opt in ('-c', '--category'):
                rtnargs['category'] = val
            elif opt in ('-d', '--doctype'):
                rtnargs['doctype'] = val
            elif opt in ('-t', '--tempdir'):
                rtnargs['tempdir'] = val
            elif opt in ('-i', '--id'):
                rtnargs['id'] = val
            elif opt in ('-k', '--kbwhost'):
                rtnargs['kbwhost'] = val
            elif opt in ('--service'):
                rtnargs['service'] = True
            elif opt in ('--download'):
                rtnargs['download'] = True
            elif opt in ('--downloadNew'):
                rtnargs['downloadNew'] = True
            elif opt in ('--downloadAll'):
                rtnargs['downloadAll'] = True
            elif opt in ('--mail'):
                rtnargs['mail'] = val
            elif opt in ('--debug'):
                rtnargs['debug'] = True
    except TypeError:
        print opts
        raise

    if rtnargs['debug']:
        print opts

    return rtnargs


if __name__ == '__main__':
    ARGS = getOptions(sys.argv[1:])

    # if not bool(ARGS['username']) or not bool(ARGS['password']):
    #    print "No SSO credential."
    #    sys.exit(0)

    KBW = KbWrapper(ARGS['username'], ARGS['password'], ARGS['tempdir'])
    if ARGS['debug']: KBW.log.setLevel(logging.DEBUG)

    if ARGS['help']:
        print ''' TODO: type help menu.
        --download or --downloadNew or --service
        '''
        sys.exit(0)

    if ARGS['service']:
        # You need to change host and port
        sv = ThreadingTCPServer(('', 12345), KbWrapServer)
        print 'listen to: ', sv.socket.getsockname()
        sv.serve_forever()
    else:
        text = KBW.runner(ARGS)

        if text is None:
            KBW.pingSSO()
        else:
            print text
