#!/usr/bin/env python3
import requests

### change hostname and port, and credential ###
url = 'https://NEXUS_HOSTNAME:5000/v2/'
auth = ('admin', 'admin123')

headers = {'Accept': 'application/json'}
session = requests.Session()
s = requests.Session()
s.headers.update(headers)
s.auth = auth


def get_repos():
    r = session.get(url + '_catalog')
    r_data = r.json()
    for repo in r_data['repositories']:
        yield repo


def get_tags(repo):
    r = session.get(url + repo + '/tags/list')
    r_data = r.json()
    for tag in r_data['tags']:
        yield tag


def get_blobs(repo, tag):
    r = session.get(url + repo + '/manifests/' + tag)
    r_data = r.json()
    if "fsLayers" in r_data:
        for layer in r_data['fsLayers']:
            yield layer['blobSum']
    else:
        print(f'# ERROR: {repo}:{tag} MISSING BLOBS')


def check_blob(repo, blob):
    r = session.head(url + repo + '/blobs/' + blob)
    print(f'{r.status_code} {repo}:{blob}')


def main():
    for repo in get_repos():
        for tag in get_tags(repo):
            print(f'-- {repo}:{tag}')
            for blob in get_blobs(repo, tag):
                check_blob(repo, blob)


if __name__ == "__main__":
    main()
