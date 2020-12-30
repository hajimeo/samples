#! /usr/bin/env python3
# @see: https://ldaptor.readthedocs.io/en/latest/cookbook/ldap-proxy.html
#       https://github.com/twisted/ldaptor
#
# python3 -m pip install ldaptor
# curl -O -L https://raw.githubusercontent.com/hajimeo/samples/master/python/ldapproxy.py
# python3 ./ldapproxy.py 10389 node-freeipa.standalone.localdomain 389 # or 636 ssl

from ldaptor.protocols import pureldap
from ldaptor.protocols.ldap.ldapclient import LDAPClient
from ldaptor.protocols.ldap.ldapconnector import connectToLDAPEndpoint
from ldaptor.protocols.ldap.proxybase import ProxyBase
from twisted.internet import defer, protocol, reactor
from twisted.python import log
from functools import partial
import sys
from collections import OrderedDict
from time import time


class LoggingProxy(ProxyBase):
    """
    A simple example of using `ProxyBase` to log requests and responses.
    """
    simple_cache = OrderedDict()
    simple_cache_size = 10      # -1 is unlimited size. 0 is no cache and always use remote.
    simple_cache_ttl_sec = 300  # 0 or lower also disable cache
    is_dummy_response = True   # If True, return some dummy responses TODO: need more work.

    def handleBeforeForwardRequest(self, request, controls, reply):
        """
        Read cache
        @see: https://github.com/twisted/ldaptor/blob/master/ldaptor/test/test_proxybase.py#L25
        """
        if self.is_dummy_response:
            if isinstance(request, pureldap.LDAPBindRequest):
                reply(pureldap.LDAPBindResponse(0))
                return defer.succeed(None)
            if isinstance(request, pureldap.LDAPSearchRequest):
                # NOTE: Check the Request output and change objectName and attributes values
                # Request => LDAPSearchRequest(baseObject=b'cn=users,cn=accounts,dc=standalone,dc=localdomain', scope=1, derefAliases=3, sizeLimit=1, timeLimit=0, typesOnly=0, filter=LDAPFilter_and(value=[LDAPFilter_equalityMatch(attributeDesc=BEROctetString(value=b'objectClass'), assertionValue=BEROctetString(value=b'person')), LDAPFilter_equalityMatch(attributeDesc=BEROctetString(value=b'uid'), assertionValue=BEROctetString(value=b'hosako'))]), attributes=[b'uid', b'cn', b'mail', b'memberOf'])
                reply(pureldap.LDAPSearchResultEntry(objectName=b'uid=hosako,'+request.baseObject, attributes=[(b'uid', [b'hosako']), (b'cn', [b'Hajime Osako'])]))
                reply(pureldap.LDAPSearchResultDone(0))
                return defer.succeed(None)

        response = self.read_cache(self.hashing(request))
        if response is not None:
            log.msg("Request => " + repr(request))
            log.msg("Response => " + repr(response))
            reply(response)
            if isinstance(response, pureldap.LDAPSearchResultEntry):
                reply(pureldap.LDAPSearchResultDone(0))
            return defer.succeed(None)
        return defer.succeed((request, controls))

    def handleProxiedResponse(self, response, request, controls):
        """
        Log the representation of the responses received.
        """
        log.msg("Request => " + repr(request))
        log.msg("Response => " + repr(response))
        # Should cache only ldaptor.protocols.pureldap.LDAPSearchResultEntry?
        # if isinstance(response, pureldap.LDAPSearchResultEntry):
        self.save_cache(self.hashing(request), response)
        return defer.succeed(response)

    def hashing(self, obj):
        # TODO: If obj is dict, causes TypeError: unhashable type: 'dict', and not sure if below is correct
        if type(obj) == dict:
            return hash(tuple(obj))
        return hash(obj)

    def maintain_cache(self):
        current_size = len(self.simple_cache)
        if bool(current_size) is False:
            return
        copy_simple_cache = self.simple_cache.copy()
        for cKey, d in copy_simple_cache.items():
            # Check the size of objects, and delete old one (with popitem()?)
            if self.simple_cache_size > -1 and len(self.simple_cache) > self.simple_cache_size:
                del self.simple_cache[cKey]
                continue
            # Check the time of items and delete old one
            for ts, data in d.items():
                if ts < (time() - self.simple_cache_ttl_sec):
                    del self.simple_cache[cKey]
        del copy_simple_cache
        log.msg("maintain_cache-ed from %d to %d" %
                (current_size, len(self.simple_cache)))

    def save_cache(self, cKey, data):
        ts = time()
        if self.simple_cache_size > -1 and data is not None:
            self.simple_cache[cKey] = {ts: data}
            log.msg("save_cache-ed for %s : type %s" %
                    (str(cKey), str(type(data))))
        # If None is given, delete this item
        elif cKey in self.simple_cache:
            del self.simple_cache[cKey]

    def read_cache(self, cKey):
        # maintain cache before reading to delete obsolete data
        self.maintain_cache()
        if self.simple_cache_size > -1 and cKey in self.simple_cache:
            if len(self.simple_cache[cKey]) != 1:
                log.msg("read_cache: size of %s is %d" %
                        (str(cKey), len(self.simple_cache[cKey])))
                return None
            # as it should contain only one dict, returning the first value from the dict_values
            for ts, data in self.simple_cache[cKey].items():
                log.msg("read_cache-ed for %s : ts %s : type %s" %
                        (str(cKey), str(ts), str(type(data))))
                return data
        # Returning None means no match
        return None


def ldapBindRequestRepr(self):
    l = []
    l.append('version={0}'.format(self.version))
    l.append('dn={0}'.format(repr(self.dn)))
    l.append('auth=****')
    if self.tag != self.__class__.tag:
        l.append('tag={0}'.format(self.tag))
    l.append('sasl={0}'.format(repr(self.sasl)))
    return self.__class__.__name__ + '(' + ', '.join(l) + ')'


pureldap.LDAPBindRequest.__repr__ = ldapBindRequestRepr

if __name__ == '__main__':
    """
    Demonstration LDAP proxy; listens on localhost:10389 and
    passes all requests to localhost:8080.
    """
    log.startLogging(sys.stderr)

    port = '10389'
    ldap_host = 'localhost'
    ldap_port = '389'  # or '636' with 'ssl' below
    ldap_protocol = 'tcp'  # or 'ssl'
    if (len(sys.argv) > 1):
        port = sys.argv[1]
    if (len(sys.argv) > 2):
        ldap_host = sys.argv[2]
    if (len(sys.argv) > 3):
        ldap_port = sys.argv[3]
    if (len(sys.argv) > 4):
        ldap_protocol = sys.argv[4]

    if int(port) == int(ldap_port) and ldap_host in ['localhost', '127.0.0.1']:
        log.msg("port %d and ldap_port is same" % int(port))
        sys.exit(1)

    factory = protocol.ServerFactory()
    proxiedEndpointStr = '%s:host=%s:port=%s' % (
        ldap_protocol, ldap_host, ldap_port)
    use_tls = False
    if ldap_protocol == 'ssl':
        ldap_protocol = True

    clientConnector = partial(
        connectToLDAPEndpoint,
        reactor,
        proxiedEndpointStr,
        LDAPClient)

    def buildProtocol():
        proto = LoggingProxy()
        proto.clientConnector = clientConnector
        proto.use_tls = use_tls
        return proto

    factory.protocol = buildProtocol
    reactor.listenTCP(int(port), factory)
    reactor.run()
