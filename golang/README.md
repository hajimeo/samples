To compile, using below bash function:
```
function goBuild() 
{ 
    local _goFile="$1";
    local _name="$2";
    local _destDir="${3:-"$HOME/IdeaProjects/samples/misc"}";
    [ -z "${_name}" ] && _name="$(basename "${_goFile}" ".go" | tr '[:upper:]' '[:lower:]')";
    env GOOS=linux GOARCH=amd64 go build -o "${_destDir%/}/${_name}_Linux_x86_64" ${_goFile} && env GOOS=darwin GOARCH=amd64 go build -o "${_destDir%/}/${_name}_Darwin_x86_64" ${_goFile} && env GOOS=darwin GOARCH=arm64 go build -o "${_destDir%/}/${_name}_Darwin_arm64" ${_goFile} || return $?;
    ls -l ${_destDir%/}/${_name}_* || return $?
    echo "curl -o /usr/local/bin/${_name} -L \"https://github.com/hajimeo/samples/raw/master/misc/${_name}_\$(uname)_\$(uname -m)\""
}
```
