To compile, use the `goBuild` from bash_aliases.sh: https://github.com/hajimeo/samples/blob/096e79309d9f21c8ccdde18687c21973798849bc/runcom/bash_aliases.sh#L793-L837  
When a Golang module uses "helpers", may want to use *one* of the following commands:
```
go get -u -t -v github.com/hajimeo/samples/golang/helpers@latest
go mod edit -replace github.com/hajimeo/samples/golang/helpers=$HOME/IdeaProjects/samples/golang/helpers
```
 and maybe `go list -m -u all && go get -u all` (`go get -u ./...`), and `go mod tidy`.