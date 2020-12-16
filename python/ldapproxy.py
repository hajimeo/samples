#! /usr/bin/env python3
# @see: https://ldaptor.readthedocs.io/en/latest/cookbook/ldap-proxy.html
#       https://github.com/twisted/ldaptor
#
#       python3 -m pip install ldaptor

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
    simple_cache = OrderedDict()
    simple_cache_size = 10
    simple_cache_ttl_sec = 300

    """
    A simple example of using `ProxyBase` to log requests and responses.
    """

    def handleBeforeForwardRequest(self, request, controls, reply):
        """
        Read cache
        @see: https://github.com/twisted/ldaptor/blob/master/ldaptor/test/test_proxybase.py#L25
        """
        response = self.read_cache(self.hashing(request))
        if response is not None:
            reply(response)
            return defer.succeed(None)
        return defer.succeed((request, controls))

    def handleProxiedResponse(self, response, request, controls):
        """
        Log the representation of the responses received.
        """
        log.msg("Request => " + repr(request))
        log.msg("Response => " + repr(response))
        self.save_cache(self.hashing(request), response)
        return defer.succeed(response)

    @staticmethod
    def hashing(text):
        return abs(hash(repr(text))) % (10 ** 8)

    def maintain_cache(self):
        current_size = len(self.simple_cache)
        for hash, d in self.simple_cache.items():
            # Check the size of objects, and delete old one (with popitem()?)
            if len(self.simple_cache) > self.simple_cache_size:
                del self.simple_cache[hash]
                continue
            # Check the time of items and delete old one
            for ts, data in d.items():
                if ts < time() - self.simple_cache_ttl_sec:
                    del self.simple_cache[hash]
        log.msg("maintain_cache-ed from %d to %d" % (current_size, len(self.simple_cache)))

    def save_cache(self, hash, data):
        ts = time()
        if data is not None:
            self.simple_cache[hash] = {ts: data}
        # If None is given, delete this item
        elif hash in self.simple_cache:
            del self.simple_cache[hash]

    def read_cache(self, hash):
        # maintain cache before reading to delete obsolete data
        self.maintain_cache()
        if hash in self.simple_cache:
            # as it should contain only one dict, returning the first value from the dict_values
            return next(iter(self.simple_cache[hash].values()))
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

    port = 10389
    ldap_host = 'localhost'
    ldap_port = '389'
    if (len(sys.argv) > 3):
        port = sys.argv[1]
        ldap_host = sys.argv[2]
        ldap_port = sys.argv[3]
    elif (len(sys.argv) > 2):
        port = sys.argv[1]
        ldap_host = sys.argv[2]
    elif (len(sys.argv) > 1):
        port = sys.argv[1]

    factory = protocol.ServerFactory()
    proxiedEndpointStr = 'tcp:host=%s:port=%s' % (ldap_host, ldap_port)
    use_tls = False
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
    reactor.listenTCP(port, factory)
    reactor.run()
