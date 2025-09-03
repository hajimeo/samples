To compile, using below bash function:
```bash
function goBuild() {
    local _goFile="$1"
    local _name="$2"
    local _destDir="${3:-"$HOME/IdeaProjects/samples/misc"}"
    [ -z "${_name}" ] && _name="$(basename "${_goFile}" ".go" | tr '[:upper:]' '[:lower:]')"
    if [ -d /opt/homebrew/opt/go/libexec ]; then
        export GOROOT=/opt/homebrew/opt/go/libexec
    fi
    env GOOS=linux GOARCH=amd64 go build -o "${_destDir%/}/${_name}_Linux_x86_64" ${_goFile} && \
    env GOOS=linux GOARCH=arm64 go build -o "${_destDir%/}/${_name}_Linux_aarch64" ${_goFile} && \
    env GOOS=darwin GOARCH=amd64 go build -o "${_destDir%/}/${_name}_Darwin_x86_64" ${_goFile} && \
    env GOOS=darwin GOARCH=arm64 go build -o "${_destDir%/}/${_name}_Darwin_arm64" ${_goFile} || return $?
    env GOOS=windows GOARCH=amd64 go build -o "${_destDir%/}/${_name}_Windows_x86_64" ${_goFile}
    ls -l ${_destDir%/}/${_name}_* || return $?
    echo "curl -o /usr/local/bin/${_name} -L \"https://github.com/hajimeo/samples/raw/master/misc/${_name}_\$(uname)_\$(uname -m)\""
    date
}
```
When a Golang module uses "helpers", may want to use *one* of the following commands:
```
go get -u -t -v github.com/hajimeo/samples/golang/helpers@latest
go mod edit -replace github.com/hajimeo/samples/golang/helpers=$HOME/IdeaProjects/samples/golang/helpers
```
 and maybe `go list -m -u all && go get -u all` (`go get -u ./...`), and `go mod tidy`.