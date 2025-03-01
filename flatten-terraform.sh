rm -rf flattened
mkdir -p flattened

find  ./terraform -type f \
  -not -path '*/\.*' \
  -not -name '*cache*' \
  -not -name '*lock*' \
  -not -name '*provider*' \
  -not -name '*.backup' \
  -not -name '*.tfstate*' \
  -exec sh -c 'cp "$1" "./flattened/$(dirname "$1" | sed "s/[\/.]/-/g")-$(basename "$1")"' _ {} \;

find  ./helm -type f \
  -not -path '*/\.*' \
  -not -name '*cache*' \
  -not -name '*lock*' \
  -not -name '*provider*' \
  -not -name '*.backup' \
  -not -name '*.tfstate*' \
  -exec sh -c 'cp "$1" "./flattened/$(dirname "$1" | sed "s/[\/.]/-/g")-$(basename "$1")"' _ {} \;

find  . -type f \
  -not -path '*/\.*' \
  -not -name '*cache*' \
  -not -name '*lock*' \
  -not -name '*provider*' \
  -not -name '*.backup' \
  -not -name '*.tfstate*' \
  -exec sh -c 'cp "$1" "./flattened/$(dirname "$1" | sed "s/[\/.]/-/g")-$(basename "$1")"' _ {} \;


tree . >> flattened/filetree.txt