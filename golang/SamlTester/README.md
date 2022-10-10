# Simplest SAML IdP
For Unit / Integ tests, based on https://github.com/d-rk/mini-saml-idp.

## Download / install
```
curl -o ./simplesamlidp -L https://github.com/hajimeo/samples/raw/master/misc/simplesamlidp_$(uname);
chmod u+x ./simplesamlidp;
curl -O -L https://raw.githubusercontent.com/hajimeo/samples/master/misc/simple-saml-idp.json;
```

## How to Start
### If you do not have some key and cert for your SAML IdP, create
```
openssl req -x509 -newkey rsa:2048 -keyout ./myidp.key -out ./myidp.crt -days 365 -nodes -subj "/CN=$(hostname -f)"
```
### Set environment variable then start
```
export IDP_KEY=./myidp.key IDP_CERT=./myidp.crt USER_JSON=./simple-saml-idp.json IDP_BASE_URL="http://localhost:2080/" SERVICE_METADATA_URL="./service-metadata.xml"
./simplesamlidp
```
### Set up SAML on your Service
To get IdP's metadata, access "${IDP_BASE_URL%/}/metadata"
```
curl "${IDP_BASE_URL%/}/metadata"
```
If your Service is NXRM3, just paste above metadata XML and save (and add SAML Realm).
Then download Service's metadata into SERVICE_METADATA_URL:
```
curl -o ${SERVICE_METADATA_URL} -u "admin:admin123" "http://localhost:8081/service/rest/v1/security/saml/metadata"
```
NOTE: If above service is not registered, please restart "./simplesamlidp" (ctrl+c to stop)
### Test SAML login (eg: "samluser")
